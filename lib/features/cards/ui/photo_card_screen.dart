import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app_config.dart';
import '../../../core/data/attachment_store.dart';
import '../../../core/data/notes_repository.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/services/ocr_service.dart';
import '../../../core/services/reminder_service.dart';
import '../../../core/theme/varna_colors.dart';
import '../../papers/logic/expiry_date_parser.dart';
import '../../papers/logic/renewals_logic.dart';
import '../../papers/ui/renewal_actions.dart';
import 'widgets/attachment_image.dart';
import 'widgets/card_actions.dart';
import 'widgets/card_saver.dart';
import 'widgets/card_title_field.dart';
import 'widgets/card_unavailable.dart';
import 'widgets/color_dots.dart';
import 'widgets/format_utils.dart';
import 'widgets/tinted_card_scaffold.dart';
import 'widgets/ui_kit.dart';

/// Viewer/editor for photo and scan cards: zoomable page(s), editable title,
/// extracted text (scans) and the renewal date of a paper.
class PhotoCardScreen extends ConsumerWidget {
  const PhotoCardScreen({super.key, required this.cardId});

  final String cardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<NoteCard?> card = ref.watch(cardProvider(cardId));
    return card.when(
      loading: () => const CardLoading(),
      error: (Object e, StackTrace s) => const CardUnavailable(error: true),
      data: (NoteCard? value) {
        if (value == null) {
          return const CardUnavailable();
        }
        return _PhotoEditor(card: value);
      },
    );
  }
}

class _PhotoEditor extends ConsumerStatefulWidget {
  const _PhotoEditor({required this.card});

  final NoteCard card;

  @override
  ConsumerState<_PhotoEditor> createState() => _PhotoEditorState();
}

class _PhotoEditorState extends ConsumerState<_PhotoEditor> {
  late final NotesRepository _repo;
  late final AttachmentStore _attachments;
  late final ReminderService _reminders;
  late final OcrService _ocr;
  late final CardSaver _saver;
  late final Autosaver _autosaver;
  late final AutosaveLifecycleFlusher _flusher;
  late final TextEditingController _title;
  final FocusNode _titleFocus = FocusNode();
  final PageController _pages = PageController();

  int _page = 0;
  bool _zoomed = false;
  bool _ocrBusy = false;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(notesRepositoryProvider);
    _attachments = ref.read(attachmentStoreProvider);
    _reminders = ref.read(reminderServiceProvider);
    _ocr = ref.read(ocrServiceProvider);
    _saver = CardSaver(_repo, widget.card.id);
    _title = TextEditingController(text: widget.card.title);
    _autosaver = Autosaver(onSave: _saveTitle);
    _flusher = AutosaveLifecycleFlusher(_autosaver);
  }

  Future<void> _saveTitle() async {
    final String title = _title.text;
    await _saver.update((NoteCard c) {
      return c.title == title ? c : c.copyWith(title: title);
    });
  }

  @override
  void didUpdateWidget(_PhotoEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool editing = _autosaver.hasPendingChanges ||
        _autosaver.isSaving ||
        _titleFocus.hasFocus;
    if (!editing && _title.text != widget.card.title) {
      _title.text = widget.card.title;
    }
  }

  @override
  void dispose() {
    _flusher.detach();
    // Saves what is still pending (nothing after a delete: it was cancelled).
    _autosaver.dispose();
    _title.dispose();
    _titleFocus.dispose();
    _pages.dispose();
    super.dispose();
  }

  List<Attachment> get _images => widget.card.attachments
      .where((Attachment a) => a.kind == AttachmentKind.image)
      .toList();

  Future<void> _goBack() async {
    await _autosaver.flush();
    if (!mounted) {
      return;
    }
    leaveScreen(context);
  }

  Future<void> _deleteCard() async {
    final bool ok = await confirmDelete(context);
    if (!ok || !mounted) {
      return;
    }
    // The screen is replaced as soon as the card is gone, so leave through a
    // router captured now.
    final GoRouter router = GoRouter.of(context);
    _autosaver.cancel();
    final bool done = await deleteCardFromEditor(
      repository: _repo,
      reminders: _reminders,
      cardId: widget.card.id,
    );
    if (!done) {
      if (mounted) {
        _autosaver.markChanged();
        showInfo(context, 'Could not delete this card. Please try again.');
      }
      return;
    }
    leaveWithRouter(router);
  }

  Future<void> _shareCurrentImage() async {
    final List<Attachment> images = _images;
    if (images.isEmpty) {
      showInfo(context, 'There is no image to share.');
      return;
    }
    final Attachment att = images[math.min(_page, images.length - 1)];
    final Uint8List? bytes = await _attachments.read(att.id);
    if (!mounted) {
      return;
    }
    if (bytes == null) {
      showInfo(context, 'This image is not on this device yet.');
      return;
    }
    await shareImageBytes(
      context,
      bytes: bytes,
      fileName: att.fileName.isEmpty ? 'varna-image.jpg' : att.fileName,
    );
  }

  Future<void> _runOcr() async {
    if (_ocrBusy) {
      return;
    }
    setState(() => _ocrBusy = true);
    String text = '';
    try {
      final List<String> parts = <String>[];
      for (final Attachment att in _images) {
        final String? path = await _attachments.localPath(att.id);
        if (path == null) {
          continue;
        }
        try {
          final OcrResult result = await _ocr.recognizeFile(path);
          if (!result.isEmpty) {
            parts.add(result.text.trim());
          }
        } catch (_) {
          // One unreadable page should not stop the others.
        }
      }
      text = parts.join('\n\n');
      if (text.isNotEmpty) {
        await _saver.update((NoteCard c) => c.copyWith(ocrText: text));
      }
    } finally {
      if (mounted) {
        setState(() => _ocrBusy = false);
      }
    }
    if (mounted && text.isEmpty) {
      showInfo(context, 'No text was found in this image.');
    }
  }

  Future<void> _pickRenewalDate({DateTime? preset}) async {
    final DateTime now = DateTime.now();
    final DateTime? current = widget.card.expiryDate;
    DateTime? picked = preset;
    if (picked == null) {
      final DateTime initial = current != null
          ? DateTime(current.year, current.month, current.day)
          : DateTime(now.year, now.month, now.day + 30);
      final DateTime firstDate = kRenewalPickerFirstDate;
      final DateTime lastDate = DateTime(now.year + 30, 12, 31);
      picked = await showDatePicker(
        context: context,
        initialDate: clampPickerDate(initial, firstDate, lastDate),
        firstDate: firstDate,
        lastDate: lastDate,
        helpText: 'Renewal date',
      );
    }
    if (picked == null || !mounted) {
      return;
    }
    final bool isPlus = ref.read(isPlusProvider).value ?? false;
    final String guess = guessPaperFolder(
      '${widget.card.title} ${widget.card.ocrText ?? ''}',
    );
    final DateTime date = picked;
    final RenewalReminderResult result = await saveRenewalDate(
      saver: _saver,
      card: widget.card,
      expiry: date,
      remind: true,
      isPlus: isPlus,
      reminders: _reminders,
      folder: widget.card.paperFolder ?? guess,
    );
    if (!mounted) {
      return;
    }
    final String? message = describeRenewalResult(result, date);
    showInfo(context, message ?? 'Renewal date saved.');
  }

  Future<void> _removeRenewalDate() async {
    await _saver.update(
      (NoteCard c) => c.copyWith(expiryDate: null, reminderAt: null),
    );
    // The reminder belonged to the date that was just removed.
    try {
      await _reminders.cancel(widget.card.id);
    } catch (_) {
      // A leftover notification is harmless.
    }
  }

  Future<void> _remindBeforeRenewal() async {
    final DateTime? expiry = widget.card.expiryDate;
    if (expiry == null) {
      return;
    }
    final bool isPlus = ref.read(isPlusProvider).value ?? false;
    final RenewalReminderResult result = await saveRenewalDate(
      saver: _saver,
      card: widget.card,
      expiry: expiry,
      remind: true,
      isPlus: isPlus,
      reminders: _reminders,
    );
    if (!mounted) {
      return;
    }
    showInfo(context, describeRenewalResult(result, expiry) ?? 'Done.');
  }

  @override
  Widget build(BuildContext context) {
    final VarnaColors colors = VarnaColors.of(context);
    final NoteCard card = widget.card;
    final AsyncValue<Notebook?> notebook =
        ref.watch(notebookProvider(card.notebookId));
    final AsyncValue<AppSettings> settings = ref.watch(settingsProvider);
    final SyncProviderId? provider = settings.value?.syncProvider;
    final bool isPlus = ref.watch(isPlusProvider).value ?? false;
    final List<Attachment> images = _images;
    final bool isScan = card.type == CardType.scan;
    final bool isPaper = isScan || card.expiryDate != null;
    final String ocrText = (card.ocrText ?? '').trim();

    final String kind = isScan ? 'Scan' : 'Photo';
    final String pages = images.length == 1 ? '1 page' : '${images.length} pages';
    final String notebookName = notebook.value?.title ?? '';
    final String meta = <String>[
      if (notebookName.isNotEmpty) notebookName,
      isScan ? '$kind, $pages' : kind,
      'edited ${editedLabel(card.updatedAt, DateTime.now())}',
    ].join(', ');

    final double viewerHeight = math.max(
      240.0,
      math.min(MediaQuery.sizeOf(context).height * 0.5, 460.0),
    );

    final Widget viewer = ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: viewerHeight,
        color: Colors.black.withValues(alpha: 0.08),
        child: images.isEmpty
            ? Center(
                child: Text(
                  'No image on this card',
                  style: bodyStyle(context, 15, color: colors.muted),
                ),
              )
            : PageView.builder(
                controller: _pages,
                physics: _zoomed
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
                itemCount: images.length,
                onPageChanged: (int index) => setState(() => _page = index),
                itemBuilder: (BuildContext context, int index) {
                  return _ZoomablePage(
                    key: ValueKey<String>(images[index].id),
                    attachmentId: images[index].id,
                    onZoomChanged: (bool zoomed) {
                      if (zoomed != _zoomed) {
                        setState(() => _zoomed = zoomed);
                      }
                    },
                  );
                },
              ),
      ),
    );

    final Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 22),
        CardTitleField(
          controller: _title,
          focusNode: _titleFocus,
          hintText: isScan ? 'Name this scan' : 'Name this photo',
          onChanged: (_) => _autosaver.markChanged(),
        ),
        const SizedBox(height: 6),
        Text(meta, style: bodyStyle(context, 13, weight: FontWeight.w600)),
        const SizedBox(height: 16),
        viewer,
        if (images.length > 1) ...<Widget>[
          const SizedBox(height: 12),
          _PageDots(count: images.length, index: math.min(_page, images.length - 1)),
        ],
        if (isScan || ocrText.isNotEmpty) ...<Widget>[
          const SizedBox(height: 20),
          _ExtractedText(
            text: ocrText,
            busy: _ocrBusy,
            canRun: _ocr.isSupported && images.isNotEmpty,
            onRun: () => unawaited(_runOcr()),
          ),
        ],
        if (isPaper) ...<Widget>[
          const SizedBox(height: 16),
          _RenewalSection(
            card: card,
            isPlus: isPlus,
            suggestion: card.expiryDate == null
                ? ExpiryDateParser.parse(ocrText)
                : null,
            onPickDate: () => unawaited(_pickRenewalDate()),
            onUseDate: (DateTime d) => unawaited(_pickRenewalDate(preset: d)),
            onRemoveDate: () => unawaited(_removeRenewalDate()),
            onRemind: () => unawaited(_remindBeforeRenewal()),
            onFolder: (String folder) {
              unawaited(_saver.update(
                (NoteCard c) => c.copyWith(paperFolder: folder),
              ));
            },
            onUpgrade: () => context.push('/paywall'),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );

    final Widget footer = Align(
      alignment: Alignment.centerLeft,
      child: CardColorDots(
        selected: card.colorIndex,
        onSelected: (int index) {
          unawaited(_saver.update(
            (NoteCard c) => c.copyWith(colorIndex: index),
          ));
        },
      ),
    );

    return TintedCardScaffold(
      tint: colors.cardColor(card.colorIndex),
      onBack: () => unawaited(_goBack()),
      status: _autosaver.status,
      destinationLabel: provider?.displayName,
      updatedAt: card.updatedAt,
      favourite: card.favourite,
      onToggleFavourite: () {
        unawaited(_saver.update(
          (NoteCard c) => c.copyWith(favourite: !c.favourite),
        ));
      },
      onDelete: () => unawaited(_deleteCard()),
      extraActions: <CardMenuAction>[
        if (images.isNotEmpty)
          CardMenuAction(
            label: 'Share image',
            icon: Icons.ios_share,
            onSelected: () => unawaited(_shareCurrentImage()),
          ),
        if (card.reminderAt != null)
          CardMenuAction(
            label: 'Remove reminder',
            icon: Icons.notifications_off_outlined,
            onSelected: () {
              unawaited(_reminders.cancel(card.id));
              unawaited(_saver.update(
                (NoteCard c) => c.copyWith(reminderAt: null),
              ));
            },
          ),
      ],
      content: content,
      footer: footer,
    );
  }
}

/// One zoomable page. Reports whether it is zoomed in so the page view can
/// stop swiping while the user pans the image.
class _ZoomablePage extends StatefulWidget {
  const _ZoomablePage({
    super.key,
    required this.attachmentId,
    required this.onZoomChanged,
  });

  final String attachmentId;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomablePage> createState() => _ZoomablePageState();
}

class _ZoomablePageState extends State<_ZoomablePage> {
  final TransformationController _controller = TransformationController();
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTransform);
  }

  void _onTransform() {
    final bool zoomed = _controller.value.getMaxScaleOnAxis() > 1.02;
    if (zoomed != _zoomed) {
      _zoomed = zoomed;
      widget.onZoomChanged(zoomed);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTransform);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: () => _controller.value = Matrix4.identity(),
      child: InteractiveViewer(
        transformationController: _controller,
        minScale: 1,
        maxScale: 6,
        child: Center(
          child: AttachmentImage(
            attachmentId: widget.attachmentId,
            fit: BoxFit.contain,
            semanticLabel: 'Scanned page',
          ),
        ),
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final VarnaColors colors = VarnaColors.of(context);
    return Semantics(
      label: 'Page ${index + 1} of $count',
      child: ExcludeSemantics(
        child: Column(
          children: <Widget>[
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (int i = 0; i < count; i++)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == index
                          ? colors.ink
                          : colors.ink.withValues(alpha: 0.25),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Page ${index + 1} of $count',
              style: bodyStyle(context, 13, weight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExtractedText extends StatelessWidget {
  const _ExtractedText({
    required this.text,
    required this.busy,
    required this.canRun,
    required this.onRun,
  });

  final String text;
  final bool busy;
  final bool canRun;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final VarnaColors colors = VarnaColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
      decoration: BoxDecoration(
        color: frostedWhite(),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Extracted text',
                  style: bodyStyle(context, 13, weight: FontWeight.w700),
                ),
              ),
              if (text.isNotEmpty)
                IconButton(
                  tooltip: 'Copy text',
                  icon: const Icon(Icons.copy_outlined, size: 20),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: text));
                    if (context.mounted) {
                      showInfo(context, 'Text copied.');
                    }
                  },
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _body(context, colors),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, VarnaColors colors) {
    if (text.isNotEmpty) {
      return SelectableText(
        text,
        style: bodyStyle(context, 15, height: 1.45),
      );
    }
    if (busy) {
      return Row(
        children: <Widget>[
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Reading the text...',
              style: bodyStyle(context, 15, color: colors.muted),
            ),
          ),
        ],
      );
    }
    if (canRun) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'No text has been read from this scan yet.',
            style: bodyStyle(context, 15, color: colors.muted, height: 1.4),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(88, 48),
              side: BorderSide(color: colors.ink, width: 2),
            ),
            onPressed: onRun,
            child: const Text('Run text recognition'),
          ),
        ],
      );
    }
    return Text(
      'Text recognition runs in the ${AppConfig.appName} mobile app.',
      style: bodyStyle(context, 15, color: colors.muted, height: 1.4),
    );
  }
}

class _RenewalSection extends StatelessWidget {
  const _RenewalSection({
    required this.card,
    required this.isPlus,
    required this.suggestion,
    required this.onPickDate,
    required this.onUseDate,
    required this.onRemoveDate,
    required this.onRemind,
    required this.onFolder,
    required this.onUpgrade,
  });

  final NoteCard card;
  final bool isPlus;
  final DateTime? suggestion;
  final VoidCallback onPickDate;
  final ValueChanged<DateTime> onUseDate;
  final VoidCallback onRemoveDate;
  final VoidCallback onRemind;
  final ValueChanged<String> onFolder;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final VarnaColors colors = VarnaColors.of(context);
    final DateTime? expiry = card.expiryDate;
    final DateTime? hint = suggestion;
    String dateText = 'Not set';
    if (expiry != null) {
      final int days = RenewalsLogic.daysUntil(expiry, DateTime.now());
      dateText = '${formatDate(expiry)} (${RenewalsLogic.dueLabel(days).toLowerCase()})';
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: frostedWhite(),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Renewal date',
            style: bodyStyle(context, 13, weight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(dateText, style: bodyStyle(context, 17, weight: FontWeight.w600)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: <Widget>[
              TextButton(
                style: TextButton.styleFrom(foregroundColor: colors.ink),
                onPressed: onPickDate,
                child: Text(expiry == null ? 'Set date' : 'Change date'),
              ),
              if (expiry != null)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: colors.danger),
                  onPressed: onRemoveDate,
                  child: const Text('Remove date'),
                ),
            ],
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: TextButton(
                style: TextButton.styleFrom(foregroundColor: colors.link),
                onPressed: () => onUseDate(hint),
                child: Text(
                  'Use ${formatDate(hint)}, found in the text',
                  textAlign: TextAlign.start,
                ),
              ),
            ),
          if (expiry != null) ...<Widget>[
            const SizedBox(height: 8),
            Text('Folder', style: bodyStyle(context, 13, weight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final String folder in RenewalsLogic.folders)
                  FilterPill(
                    label: folder,
                    selected:
                        RenewalsLogic.normalizeFolder(card.paperFolder) == folder,
                    onTap: () => onFolder(folder),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (isPlus) ...<Widget>[
              Text(
                card.reminderAt != null
                    ? 'Reminder: ${formatDateTime(card.reminderAt!)}'
                    : 'No reminder set.',
                style: bodyStyle(context, 14, color: colors.muted),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: colors.ink),
                onPressed: onRemind,
                child: Text('Remind me $kRenewalLeadDays days before'),
              ),
            ] else ...<Widget>[
              Text(
                'Renewal reminders are part of ${AppConfig.appName} Plus. '
                'Your date is saved either way.',
                style: bodyStyle(context, 14, color: colors.muted, height: 1.4),
              ),
              TextButton(
                onPressed: onUpgrade,
                child: Text('See ${AppConfig.appName} Plus'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
