import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/attachment_store.dart';
import '../../../core/data/notes_repository.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/services/ai_service.dart';
import '../../../core/services/reminder_service.dart';
import '../../../core/theme/varna_colors.dart';
import 'widgets/attachment_image.dart';
import 'widgets/card_actions.dart';
import 'widgets/card_saver.dart';
import 'widgets/card_title_field.dart';
import 'widgets/card_unavailable.dart';
import 'widgets/color_dots.dart';
import 'widgets/format_utils.dart';
import 'widgets/markdown_format.dart';
import 'widgets/tinted_card_scaffold.dart';
import 'widgets/ui_kit.dart';

/// Editor for text (and link) cards: tinted background, title, body, AI
/// summary (only when AI is configured), colour dots and a formatting toolbar.
///
/// Edits are saved automatically ~600 ms after typing stops, and always when
/// the screen is left.
class TextCardScreen extends ConsumerWidget {
  const TextCardScreen({super.key, required this.cardId});

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
        return _TextCardEditor(card: value);
      },
    );
  }
}

class _TextCardEditor extends ConsumerStatefulWidget {
  const _TextCardEditor({required this.card});

  final NoteCard card;

  @override
  ConsumerState<_TextCardEditor> createState() => _TextCardEditorState();
}

class _TextCardEditorState extends ConsumerState<_TextCardEditor> {
  late final NotesRepository _repo;
  late final AttachmentStore _attachments;
  late final ReminderService _reminders;
  late final AiService _ai;
  late final CardSaver _saver;
  late final Autosaver _autosaver;
  late final TextEditingController _title;
  late final MarkdownTextEditingController _body;
  final FocusNode _titleFocus = FocusNode();
  final FocusNode _bodyFocus = FocusNode();

  bool _deleted = false;
  bool _summarising = false;
  String? _summary;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(notesRepositoryProvider);
    _attachments = ref.read(attachmentStoreProvider);
    _reminders = ref.read(reminderServiceProvider);
    _ai = ref.read(aiServiceProvider);
    _saver = CardSaver(_repo, widget.card.id);
    _title = TextEditingController(text: widget.card.title);
    _body = MarkdownTextEditingController(text: widget.card.body);
    _autosaver = Autosaver(onSave: _saveText);
  }

  /// Reads the fields synchronously (see [Autosaver]) and saves them.
  Future<void> _saveText() async {
    final String title = _title.text;
    final String body = _body.text;
    await _saver.update((NoteCard c) {
      if (c.title == title && c.body == body) {
        return c;
      }
      return c.copyWith(title: title, body: body);
    });
  }

  @override
  void didUpdateWidget(_TextCardEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Pick up changes that arrive from outside (for example a sync), but never
    // while the user is typing or has unsaved edits.
    final bool editing = _autosaver.hasPendingChanges ||
        _autosaver.isSaving ||
        _titleFocus.hasFocus ||
        _bodyFocus.hasFocus;
    if (!editing) {
      if (_title.text != widget.card.title) {
        _title.text = widget.card.title;
      }
      if (_body.text != widget.card.body) {
        _body.text = widget.card.body;
      }
    }
  }

  @override
  void dispose() {
    if (!_deleted) {
      _autosaver.dispose();
    }
    _title.dispose();
    _body.dispose();
    _titleFocus.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  Future<void> _goBack() async {
    await _autosaver.flush();
    if (!mounted) {
      return;
    }
    leaveScreen(context);
  }

  Future<void> _delete() async {
    final bool ok = await confirmDelete(context);
    if (!ok || !mounted) {
      return;
    }
    _deleted = true;
    final String id = widget.card.id;
    leaveScreen(context);
    await _reminders.cancel(id);
    await _repo.deleteCard(id);
  }

  void _apply(TextEditingValue Function(TextEditingValue) transform) {
    _body.value = transform(_body.value);
    _autosaver.markChanged();
    _bodyFocus.requestFocus();
  }

  Future<void> _addPhoto() async {
    final Attachment? attachment = await pickAndStoreImage(context, _attachments);
    if (attachment == null) {
      return;
    }
    await _saver.update((NoteCard c) => c.copyWith(
          attachments: <Attachment>[...c.attachments, attachment],
        ));
  }

  Future<void> _removePhoto(Attachment attachment) async {
    await _saver.update((NoteCard c) => c.copyWith(
          attachments: c.attachments
              .where((Attachment a) => a.id != attachment.id)
              .toList(),
        ));
    try {
      await _attachments.delete(attachment.id);
    } catch (_) {
      // A leftover blob is harmless.
    }
  }

  Future<void> _setReminder() {
    return editCardReminder(
      context: context,
      reminders: _reminders,
      saver: _saver,
      card: widget.card,
      title: _title.text,
    );
  }

  Future<void> _share(BuildContext buttonContext) async {
    final String title = _title.text.trim();
    final String body = _body.text.trim();
    final String text = <String>[
      if (title.isNotEmpty) title,
      if (body.isNotEmpty) body,
    ].join('\n\n');
    if (text.isEmpty) {
      showInfo(context, 'There is nothing to share yet.');
      return;
    }
    await shareText(buttonContext, text: text, subject: title);
  }

  Future<void> _summarise() async {
    if (_summarising) {
      return;
    }
    final String text = '${_title.text}\n\n${_body.text}'.trim();
    if (text.isEmpty) {
      showInfo(context, 'Write something first, then ask for a summary.');
      return;
    }
    setState(() => _summarising = true);
    try {
      final String answer = await _ai.ask(
        'Summarise this note in two short sentences.',
        context: <String>[text],
      );
      if (!mounted) {
        return;
      }
      setState(() => _summary = answer.trim());
    } catch (_) {
      if (mounted) {
        showInfo(context, 'Could not get a summary right now.');
      }
    } finally {
      if (mounted) {
        setState(() => _summarising = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final VarnaColors colors = VarnaColors.of(context);
    final NoteCard card = widget.card;
    final AsyncValue<Notebook?> notebook =
        ref.watch(notebookProvider(card.notebookId));
    final AsyncValue<AppSettings> settings = ref.watch(settingsProvider);
    final SyncProviderId? provider = settings.value?.syncProvider;
    final bool aiReady = _ai.isConfigured;

    final String notebookName = notebook.value?.title ?? '';
    final String edited = editedLabel(card.updatedAt, DateTime.now());
    final String meta = notebookName.isEmpty
        ? 'Edited $edited'
        : '$notebookName, edited $edited';

    final TextStyle bodyText = bodyStyle(
      context,
      17,
      color: colors.ink,
      height: 1.55,
    );

    final List<Attachment> photos = card.attachments
        .where((Attachment a) => a.kind == AttachmentKind.image)
        .toList();

    final Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 22),
        CardTitleField(
          controller: _title,
          focusNode: _titleFocus,
          onChanged: (_) => _autosaver.markChanged(),
          onSubmitted: (_) => _bodyFocus.requestFocus(),
        ),
        const SizedBox(height: 6),
        Text(meta, style: bodyStyle(context, 13, weight: FontWeight.w600)),
        const SizedBox(height: 20),
        Semantics(
          textField: true,
          label: 'Note text',
          child: TextField(
            controller: _body,
            focusNode: _bodyFocus,
            style: bodyText,
            minLines: 6,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            cursorColor: colors.ink,
            decoration: InputDecoration.collapsed(
              hintText: 'Start typing...',
              hintStyle: bodyText.copyWith(
                color: colors.ink.withValues(alpha: 0.4),
              ),
            ),
            onChanged: (_) => _autosaver.markChanged(),
          ),
        ),
        if (photos.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              for (final Attachment photo in photos)
                _PhotoThumb(
                  attachment: photo,
                  onOpen: () => showAttachmentViewer(
                    context,
                    attachmentId: photo.id,
                    onRemove: () => unawaited(_removePhoto(photo)),
                  ),
                ),
            ],
          ),
        ],
        if (card.reminderAt != null) ...<Widget>[
          const SizedBox(height: 16),
          ReminderChip(
            reminderAt: card.reminderAt!,
            onTap: () => unawaited(_setReminder()),
          ),
        ],
        if (aiReady) ...<Widget>[
          const SizedBox(height: 20),
          _SummaryBox(
            summary: _summary,
            busy: _summarising,
            onSummarise: _summarise,
          ),
        ],
        const SizedBox(height: 24),
      ],
    );

    final Widget footer = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: CardColorDots(
            selected: card.colorIndex,
            onSelected: (int index) {
              unawaited(_saver.update(
                (NoteCard c) => c.copyWith(colorIndex: index),
              ));
            },
          ),
        ),
        _Toolbar(
          hasReminder: card.reminderAt != null,
          aiReady: aiReady,
          onBold: () => _apply((TextEditingValue v) => toggleWrap(v, '**')),
          onItalic: () => _apply((TextEditingValue v) => toggleWrap(v, '*')),
          onBullets: () => _apply((TextEditingValue v) => togglePrefix(v, '- ')),
          onPhoto: () => unawaited(_addPhoto()),
          onReminder: () => unawaited(_setReminder()),
          onShare: (BuildContext c) => unawaited(_share(c)),
          onAskAi: () => unawaited(_summarise()),
        ),
      ],
    );

    return TintedCardScaffold(
      tint: colors.cardColor(card.colorIndex),
      onBack: () => unawaited(_goBack()),
      status: _autosaver.status,
      destinationLabel: provider?.displayName,
      favourite: card.favourite,
      onToggleFavourite: () {
        unawaited(_saver.update(
          (NoteCard c) => c.copyWith(favourite: !c.favourite),
        ));
      },
      onDelete: () => unawaited(_delete()),
      content: content,
      footer: footer,
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({required this.attachment, required this.onOpen});

  final Attachment attachment;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Open photo ${attachment.fileName}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onOpen,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 96,
              height: 96,
              child: AttachmentImage(attachmentId: attachment.id),
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryBox extends StatelessWidget {
  const _SummaryBox({
    required this.summary,
    required this.busy,
    required this.onSummarise,
  });

  final String? summary;
  final bool busy;
  final VoidCallback onSummarise;

  @override
  Widget build(BuildContext context) {
    final String? text = summary;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: frostedWhite(),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.auto_awesome, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'AI summary',
                  style: bodyStyle(context, 13, weight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (busy)
            const LinearProgressIndicator()
          else if (text != null && text.isNotEmpty)
            Text(text, style: bodyStyle(context, 15, height: 1.45))
          else
            TextButton(
              onPressed: onSummarise,
              child: const Text('Summarise this note'),
            ),
        ],
      ),
    );
  }
}

/// The dark pill with the formatting and action buttons.
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.hasReminder,
    required this.aiReady,
    required this.onBold,
    required this.onItalic,
    required this.onBullets,
    required this.onPhoto,
    required this.onReminder,
    required this.onShare,
    required this.onAskAi,
  });

  final bool hasReminder;
  final bool aiReady;
  final VoidCallback onBold;
  final VoidCallback onItalic;
  final VoidCallback onBullets;
  final VoidCallback onPhoto;
  final VoidCallback onReminder;
  final void Function(BuildContext buttonContext) onShare;
  final VoidCallback onAskAi;

  @override
  Widget build(BuildContext context) {
    final VarnaColors colors = VarnaColors.of(context);
    final ButtonStyle style = IconButton.styleFrom(
      foregroundColor: Colors.white,
      fixedSize: const Size(46, 46),
      minimumSize: const Size(46, 46),
      padding: EdgeInsets.zero,
    );
    final TextStyle letter = bodyStyle(
      context,
      18,
      weight: FontWeight.w700,
      color: Colors.white,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: colors.ink,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        runAlignment: WrapAlignment.center,
        children: <Widget>[
          IconButton(
            tooltip: 'Bold',
            style: style,
            onPressed: onBold,
            icon: Text('B', style: letter),
          ),
          IconButton(
            tooltip: 'Italic',
            style: style,
            onPressed: onItalic,
            icon: Text(
              'I',
              style: letter.copyWith(
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Bulleted list',
            style: style,
            onPressed: onBullets,
            icon: const Icon(Icons.format_list_bulleted, size: 22),
          ),
          IconButton(
            tooltip: 'Add photo',
            style: style,
            onPressed: onPhoto,
            icon: const Icon(Icons.image_outlined, size: 22),
          ),
          IconButton(
            tooltip: hasReminder ? 'Change reminder' : 'Set reminder',
            style: style,
            onPressed: onReminder,
            icon: Icon(
              hasReminder
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_none,
              size: 22,
            ),
          ),
          Builder(
            builder: (BuildContext buttonContext) => IconButton(
              tooltip: 'Share',
              style: style,
              onPressed: () => onShare(buttonContext),
              icon: const Icon(Icons.ios_share, size: 22),
            ),
          ),
          IconButton(
            tooltip: aiReady ? 'Ask AI' : 'Ask AI: coming soon',
            style: IconButton.styleFrom(
              backgroundColor: colors.cardColor(0),
              foregroundColor: colors.ink,
              disabledBackgroundColor: colors.cardColor(0).withValues(alpha: 0.35),
              disabledForegroundColor: colors.ink.withValues(alpha: 0.5),
              fixedSize: const Size(46, 46),
              minimumSize: const Size(46, 46),
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: aiReady ? onAskAi : null,
            icon: const Icon(Icons.auto_awesome, size: 22),
          ),
        ],
      ),
    );
  }
}
