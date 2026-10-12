import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../app_config.dart';
import '../../../core/data/attachment_store.dart';
import '../../../core/data/notes_repository.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/services/entitlements.dart';
import '../../../core/services/ocr_service.dart';
import '../../../core/services/reminder_service.dart';
import '../../../core/services/usage_limits.dart';
import '../../../core/theme/varna_colors.dart';
import '../../cards/ui/widgets/card_actions.dart';
import '../../cards/ui/widgets/card_saver.dart';
import '../../cards/ui/widgets/format_utils.dart';
import '../../cards/ui/widgets/tinted_card_scaffold.dart';
import '../../cards/ui/widgets/ui_kit.dart';
import '../../papers/logic/expiry_date_parser.dart';
import '../../papers/ui/renewal_actions.dart';

// The scanner has its own dark palette (not part of the light theme tokens).
const Color _kScanBackground = Color(0xFF0E1020);
const Color _kScanFrame = Color(0xFF262A45);
const Color _kScanMuted = Color(0xFFC9CDDD);
const Color _kScanYellow = Color(0xFFFFD45C);

class _SavedScan {
  const _SavedScan(this.card, this.ocrText);

  final NoteCard card;
  final String ocrText;
}

class _ScanPage {
  const _ScanPage(this.bytes, this.name);

  final Uint8List bytes;
  final String name;
}

/// Captures one or more pages of a paper into a scan card in [notebookId].
///
/// v1 uses the system camera one page at a time (image_picker with
/// `ImageSource.camera`) instead of a live camera preview. A live preview
/// with automatic edge detection is NOT part of v1: the yellow frame is only
/// a visual guide, and the preview shows the last captured page.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key, required this.notebookId});

  final String notebookId;

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  late final NotesRepository _repo;
  late final AttachmentStore _store;
  late final OcrService _ocr;
  late final UsageLimits _limits;
  late final Entitlements _entitlements;
  late final ReminderService _reminders;
  final ImagePicker _picker = ImagePicker();
  final List<_ScanPage> _pages = <_ScanPage>[];

  bool _busy = false;
  String _busyLabel = '';

  @override
  void initState() {
    super.initState();
    _repo = ref.read(notesRepositoryProvider);
    _store = ref.read(attachmentStoreProvider);
    _ocr = ref.read(ocrServiceProvider);
    _limits = ref.read(usageLimitsProvider);
    _entitlements = ref.read(entitlementsProvider);
    _reminders = ref.read(reminderServiceProvider);
  }

  Future<void> _capture(ImageSource source) async {
    if (_busy) {
      return;
    }
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        maxWidth: 2400,
        imageQuality: 85,
      );
      if (file == null) {
        return;
      }
      final Uint8List bytes = await file.readAsBytes();
      if (!mounted) {
        return;
      }
      setState(() => _pages.add(_ScanPage(bytes, file.name)));
    } catch (_) {
      if (mounted) {
        showInfo(
          context,
          source == ImageSource.camera
              ? 'The camera could not be opened. Check that '
                  '${AppConfig.appName} may use it in your phone settings, or '
                  'choose a photo from the gallery.'
              : 'The photo could not be opened.',
        );
      }
    }
  }

  Future<bool> _confirmDiscard() async {
    final int count = _pages.length;
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(count == 1 ? 'Discard this page?' : 'Discard $count pages?'),
          content: const Text('The pages you captured have not been saved yet.'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep scanning'),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: VarnaColors.of(dialogContext).danger,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Discard'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _close() async {
    if (_busy) {
      return;
    }
    if (_pages.isNotEmpty) {
      final bool ok = await _confirmDiscard();
      if (!ok || !mounted) {
        return;
      }
    }
    if (!mounted) {
      return;
    }
    leaveScreen(context);
  }

  Future<void> _showPages() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _kScanFrame,
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _pages.length == 1
                          ? '1 scanned page'
                          : '${_pages.length} scanned pages',
                      style: bodyStyle(
                        context,
                        16,
                        weight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: <Widget>[
                            for (int i = 0; i < _pages.length; i++)
                              _PageTile(
                                index: i,
                                page: _pages[i],
                                onRemove: () {
                                  setState(() => _pages.removeAt(i));
                                  setSheetState(() {});
                                  if (_pages.isEmpty) {
                                    Navigator.of(sheetContext).pop();
                                  }
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showScanLimit(String message) async {
    final bool? upgrade = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Scan limit reached'),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Not now'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text('See ${AppConfig.appName} Plus'),
            ),
          ],
        );
      },
    );
    if (upgrade == true && mounted) {
      unawaited(context.push('/paywall'));
    }
  }

  /// Saves the pages, reads their text and creates the card. Returns null
  /// when nothing was saved (limit reached or an error, already reported).
  Future<_SavedScan?> _saveScan() async {
    try {
      final LimitCheck check = await _limits.canScan();
      if (!mounted) {
        return null;
      }
      if (!check.allowed) {
        setState(() => _busy = false);
        await _showScanLimit(check.message);
        return null;
      }

      final DateTime now = DateTime.now();
      final List<Attachment> attachments = <Attachment>[];
      for (int i = 0; i < _pages.length; i++) {
        final String id = const Uuid().v4();
        await _store.save(id, _pages[i].bytes);
        attachments.add(Attachment(
          id: id,
          kind: AttachmentKind.image,
          fileName: 'scan-${now.millisecondsSinceEpoch}-${i + 1}.jpg',
          byteLength: _pages[i].bytes.length,
        ));
      }

      String ocrText = '';
      if (_ocr.isSupported) {
        if (mounted) {
          setState(() => _busyLabel = 'Reading the text...');
        }
        final List<String> parts = <String>[];
        for (final Attachment att in attachments) {
          final String? path = await _store.localPath(att.id);
          if (path == null) {
            continue;
          }
          try {
            final OcrResult result = await _ocr.recognizeFile(path);
            if (!result.isEmpty) {
              parts.add(result.text.trim());
            }
          } catch (_) {
            // A page that cannot be read is still saved as an image.
          }
        }
        ocrText = parts.join('\n\n');
      }

      final NoteCard card = await _repo.createCard(
        notebookId: widget.notebookId,
        type: CardType.scan,
        title: 'Scan ${formatStamp(now)}',
        colorIndex: 1,
        attachments: attachments,
        ocrText: ocrText.isEmpty ? null : ocrText,
      );
      await _limits.recordScan();
      return _SavedScan(card, ocrText);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        showInfo(context, 'The scan could not be saved. Please try again.');
      }
      return null;
    }
  }

  Future<void> _finish() async {
    if (_busy || _pages.isEmpty) {
      return;
    }
    setState(() {
      _busy = true;
      _busyLabel = 'Saving pages...';
    });
    final _SavedScan? saved = await _saveScan();
    if (saved == null) {
      return;
    }
    final DateTime? expiry = saved.ocrText.isEmpty
        ? null
        : ExpiryDateParser.parse(saved.ocrText);
    if (expiry != null && mounted) {
      setState(() => _busyLabel = '');
      try {
        await _offerReminder(saved.card, expiry, saved.ocrText);
      } catch (_) {
        // The scan is saved; the date can be set later on the card.
      }
    }
    if (!mounted) {
      return;
    }
    context.pushReplacement('/card/${saved.card.id}');
  }

  Future<void> _offerReminder(NoteCard card, DateTime found, String text) async {
    final bool isPlus = await _entitlements.isPlus();
    if (!mounted) {
      return;
    }
    final _ExpiryResult? result = await showModalBottomSheet<_ExpiryResult>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) =>
          _ExpirySheet(date: found, isPlus: isPlus),
    );
    if (result == null || result.choice == _ExpiryChoice.skip) {
      return;
    }
    final bool remind = isPlus && result.choice == _ExpiryChoice.remind;
    final RenewalReminderResult outcome = await saveRenewalDate(
      saver: CardSaver(_repo, card.id),
      card: card,
      expiry: result.date,
      remind: remind,
      isPlus: isPlus,
      reminders: _reminders,
      folder: guessPaperFolder('${card.title} $text'),
    );
    if (!mounted) {
      return;
    }
    showInfo(
      context,
      describeRenewalResult(outcome, result.date) ?? 'Renewal date saved.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final int count = _pages.length;
    final Uint8List? last = count == 0 ? null : _pages.last.bytes;

    final Widget header = Row(
      children: <Widget>[
        RoundIconButton(
          icon: Icons.close,
          tooltip: 'Close scanner',
          background: Colors.white.withValues(alpha: 0.14),
          foreground: Colors.white,
          onPressed: _busy ? null : () => unawaited(_close()),
        ),
        Expanded(
          child: Text(
            'Page ${count + 1}',
            textAlign: TextAlign.center,
            style: bodyStyle(
              context,
              15,
              weight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 44),
      ],
    );

    final Widget controls = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child:
        SizedBox(
          width: 64,
          height: 72,
          child: last == null
              ? null
              : Semantics(
                  button: true,
                  label: count == 1
                      ? 'Review 1 scanned page'
                      : 'Review $count scanned pages',
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      Positioned.fill(
                        child: Material(
                          color: VarnaColors.of(context).hairline,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: const BorderSide(color: Colors.white, width: 2),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: _busy ? null : () => unawaited(_showPages()),
                            child: Image.memory(
                              last,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                              errorBuilder: (BuildContext c, Object e, StackTrace? s) =>
                                  const SizedBox.shrink(),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: -6,
                        top: -6,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 24),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _kScanYellow,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$count',
                            textAlign: TextAlign.center,
                            style: bodyStyle(
                              context,
                              13,
                              weight: FontWeight.w700,
                              color: VarnaColors.of(context).ink,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
          ),
        ),
        Semantics(
          button: true,
          enabled: !_busy,
          label: 'Capture page',
          excludeSemantics: true,
          child: Tooltip(
            message: 'Capture page',
            child: Material(
              color: _kScanYellow,
              shape: const CircleBorder(
                side: BorderSide(color: Colors.white, width: 5),
              ),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _busy ? null : () => unawaited(_capture(ImageSource.camera)),
                child: const SizedBox(width: 84, height: 84),
              ),
            ),
          ),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: VarnaColors.of(context).ink,
              minimumSize: const Size(64, 48),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            onPressed: (_busy || count == 0) ? null : () => unawaited(_finish()),
            child: const Text('Done'),
          ),
          ),
        ),
      ],
    );

    final Widget footer = Column(
      children: <Widget>[
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: Colors.white),
          onPressed:
              _busy ? null : () => unawaited(_capture(ImageSource.gallery)),
          icon: const Icon(Icons.photo_library_outlined, size: 20),
          label: const Text('Choose from gallery'),
        ),
        Text(
          _ocr.isSupported
              ? 'Text in the scan becomes searchable on this phone.'
              : 'Reading text needs the ${AppConfig.appName} mobile app. '
                  'Your pages are still saved.',
          textAlign: TextAlign.center,
          style: bodyStyle(context, 14, color: _kScanMuted),
        ),
      ],
    );

    return PopScope(
      canPop: _pages.isEmpty && !_busy,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) {
          unawaited(_close());
        }
      },
      child: Scaffold(
        backgroundColor: _kScanBackground,
        body: SafeArea(
          child: Stack(
            children: <Widget>[
              Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
                  child: LayoutBuilder(
                    builder: (BuildContext context, BoxConstraints box) {
                      final bool roomy = box.maxHeight >= 620;
                      final Widget frame = _CameraFrame(
                        preview: last,
                        message: count == 0
                            ? 'Fill the frame with the paper, then tap the round button.'
                            : 'Page captured. Tap the round button for the next page, or Done.',
                      );
                      if (roomy) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              header,
                              const SizedBox(height: 16),
                              Expanded(child: frame),
                              const SizedBox(height: 24),
                              controls,
                              const SizedBox(height: 8),
                              footer,
                            ],
                          ),
                        );
                      }
                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            header,
                            const SizedBox(height: 16),
                            SizedBox(height: 300, child: frame),
                            const SizedBox(height: 24),
                            controls,
                            const SizedBox(height: 8),
                            footer,
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              if (_busy)
                Positioned.fill(
                  child: AbsorbPointer(
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.55),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const CircularProgressIndicator(color: _kScanYellow),
                            if (_busyLabel.isNotEmpty) ...<Widget>[
                              const SizedBox(height: 16),
                              Text(
                                _busyLabel,
                                style: bodyStyle(
                                  context,
                                  16,
                                  weight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The rounded frame with the yellow guide and corner handles. Shows the last
/// captured page as a preview.
class _CameraFrame extends StatelessWidget {
  const _CameraFrame({required this.preview, required this.message});

  final Uint8List? preview;
  final String message;

  Widget _handle() => Container(
        width: 18,
        height: 18,
        decoration: const BoxDecoration(
          color: _kScanYellow,
          shape: BoxShape.circle,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: ColoredBox(
        color: _kScanFrame,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: preview == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 48),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const Icon(
                              Icons.document_scanner_outlined,
                              size: 44,
                              color: _kScanMuted,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'No pages yet',
                              style: bodyStyle(
                                context,
                                13,
                                weight: FontWeight.w600,
                                color: _kScanMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(34, 56, 34, 76),
                      child: Image.memory(
                        preview!,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        semanticLabel: 'Last captured page',
                        errorBuilder: (BuildContext c, Object e, StackTrace? s) =>
                            const SizedBox.shrink(),
                      ),
                    ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(34, 56, 34, 76),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: _kScanYellow, width: 2),
                            borderRadius: BorderRadius.circular(6),
                            color: _kScanYellow.withValues(alpha: 0.10),
                          ),
                        ),
                      ),
                      Positioned(left: -9, top: -9, child: _handle()),
                      Positioned(right: -9, top: -9, child: _handle()),
                      Positioned(left: -9, bottom: -9, child: _handle()),
                      Positioned(right: -9, bottom: -9, child: _handle()),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _kScanYellow,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: bodyStyle(
                      context,
                      14,
                      weight: FontWeight.w700,
                      color: VarnaColors.of(context).ink,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageTile extends StatelessWidget {
  const _PageTile({
    required this.index,
    required this.page,
    required this.onRemove,
  });

  final int index;
  final _ScanPage page;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      height: 128,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.memory(
                page.bytes,
                fit: BoxFit.cover,
                semanticLabel: 'Page ${index + 1}',
                errorBuilder: (BuildContext c, Object e, StackTrace? s) =>
                    const ColoredBox(color: Colors.white24),
              ),
            ),
          ),
          Positioned(
            left: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${index + 1}',
                style: bodyStyle(
                  context,
                  13,
                  weight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: RoundIconButton(
              icon: Icons.delete_outline,
              tooltip: 'Remove page ${index + 1}',
              size: 44,
              iconSize: 20,
              background: Colors.black54,
              foreground: Colors.white,
              onPressed: onRemove,
            ),
          ),
        ],
      ),
    );
  }
}

enum _ExpiryChoice { remind, saveOnly, skip }

class _ExpiryResult {
  const _ExpiryResult(this.choice, this.date);

  final _ExpiryChoice choice;
  final DateTime date;
}

/// "Looks like this expires 18 Oct 2026 - remind me 7 days before?"
class _ExpirySheet extends StatefulWidget {
  const _ExpirySheet({required this.date, required this.isPlus});

  final DateTime date;
  final bool isPlus;

  @override
  State<_ExpirySheet> createState() => _ExpirySheetState();
}

class _ExpirySheetState extends State<_ExpirySheet> {
  late DateTime _date = widget.date;

  Future<void> _change() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(_date.year, _date.month, _date.day),
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 30, 12, 31),
      helpText: 'Renewal date',
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => _date = DateTime.utc(picked.year, picked.month, picked.day));
  }

  @override
  Widget build(BuildContext context) {
    final bool plus = widget.isPlus;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          4,
          24,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Looks like this expires ${formatDate(_date)}',
              style: displayStyle(context, 22),
            ),
            const SizedBox(height: 8),
            Text(
              plus
                  ? 'Remind me $kRenewalLeadDays days before?'
                  : 'Your date will be saved with the scan. Renewal reminders '
                      'are part of ${AppConfig.appName} Plus.',
              style: bodyStyle(context, 15, height: 1.4),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => unawaited(_change()),
                child: const Text('Not right? Change the date'),
              ),
            ),
            const SizedBox(height: 8),
            if (plus) ...<Widget>[
              FilledButton(
                onPressed: () => Navigator.of(context)
                    .pop(_ExpiryResult(_ExpiryChoice.remind, _date)),
                child: const Text('Yes, remind me'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.of(context)
                    .pop(_ExpiryResult(_ExpiryChoice.saveOnly, _date)),
                child: const Text('Save the date only'),
              ),
            ] else ...<Widget>[
              FilledButton(
                onPressed: () => Navigator.of(context)
                    .pop(_ExpiryResult(_ExpiryChoice.saveOnly, _date)),
                child: const Text('Save the date'),
              ),
            ],
            TextButton(
              onPressed: () => Navigator.of(context).pop(
                _ExpiryResult(_ExpiryChoice.skip, _date),
              ),
              child: const Text('Skip'),
            ),
          ],
        ),
      ),
    );
  }
}
