import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/notes_repository.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/services/reminder_service.dart';
import '../../../core/services/usage_limits.dart';
import '../../../core/theme/varna_colors.dart';
import '../../../shared/app_state.dart';
import '../../../shared/auth_gate.dart';
import '../../../shared/format.dart';
import '../../../shared/widgets/color_swatch_picker.dart';
import '../../../shared/widgets/tokens.dart';
import '../../../shared/widgets/varna_bottom_sheet.dart';
import '../../plus/ui/upsell_sheet.dart';

/// Result of [showNotebookDialog].
class NotebookDraft {
  const NotebookDraft(this.title, this.colorIndex);

  final String title;
  final int colorIndex;
}

/// Asks for a notebook name and/or colour. Returns null when cancelled.
Future<NotebookDraft?> showNotebookDialog(
  BuildContext context, {
  required String heading,
  required String confirmLabel,
  String initialTitle = '',
  int initialColor = 0,
  bool askTitle = true,
  bool askColor = true,
}) {
  return showDialog<NotebookDraft>(
    context: context,
    builder: (BuildContext dialogContext) => _NotebookDialog(
      heading: heading,
      confirmLabel: confirmLabel,
      initialTitle: initialTitle,
      initialColor: initialColor,
      askTitle: askTitle,
      askColor: askColor,
    ),
  );
}

class _NotebookDialog extends StatefulWidget {
  const _NotebookDialog({
    required this.heading,
    required this.confirmLabel,
    required this.initialTitle,
    required this.initialColor,
    required this.askTitle,
    required this.askColor,
  });

  final String heading;
  final String confirmLabel;
  final String initialTitle;
  final int initialColor;
  final bool askTitle;
  final bool askColor;

  @override
  State<_NotebookDialog> createState() => _NotebookDialogState();
}

class _NotebookDialogState extends State<_NotebookDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialTitle);
  late int _color = widget.initialColor;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _valid => !widget.askTitle || _controller.text.trim().isNotEmpty;

  void _submit() {
    if (!_valid) {
      return;
    }
    Navigator.of(context).pop(
      NotebookDraft(
        widget.askTitle ? _controller.text.trim() : widget.initialTitle,
        _color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final VarnaColors c = VarnaColors.of(context);
    return AlertDialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(widget.heading, style: displayStyle(context, 22)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (widget.askTitle)
              TextField(
                controller: _controller,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                maxLength: 60,
                onChanged: (String _) => setState(() {}),
                onSubmitted: (String _) => _submit(),
                style: bodyStyle(context, 16),
                decoration: InputDecoration(
                  labelText: 'Notebook name',
                  filled: true,
                  fillColor: c.ground,
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            if (widget.askTitle && widget.askColor) const SizedBox(height: 16),
            if (widget.askColor) ...<Widget>[
              Text(
                'Colour',
                style: bodyStyle(context, 13, weight: FontWeight.w700, color: c.muted),
              ),
              const SizedBox(height: 8),
              ColorSwatchPicker(
                selected: _color,
                onChanged: (int i) => setState(() => _color = i),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _valid ? _submit : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// "New notebook": checks the free limit (shows the upsell when reached),
/// asks for name and colour and creates it. Returns the notebook, or null.
Future<Notebook?> createNotebookFlow(BuildContext context, WidgetRef ref) async {
  final LimitCheck check = await ref.read(usageLimitsProvider).canCreateNotebook();
  if (!context.mounted) {
    return null;
  }
  if (!check.allowed) {
    await showUpsellSheet(context, reason: UpsellReason.notebookLimit);
    return null;
  }
  final int existing = ref.read(notebooksProvider).valueOrNull?.length ?? 0;
  final NotebookDraft? draft = await showNotebookDialog(
    context,
    heading: 'New notebook',
    confirmLabel: 'Create',
    initialColor: existing % 5,
  );
  if (draft == null) {
    return null;
  }
  return ref.read(notesRepositoryProvider).createNotebook(
        title: draft.title,
        colorIndex: draft.colorIndex,
      );
}

/// Options for a notebook: rename, colour, lock/unlock, delete.
/// [onDeleted] runs after the notebook was deleted; it must not rely on a
/// `BuildContext` that may be gone by then (capture a `GoRouter` instead).
///
/// The caller's widget can be disposed while the sheets and dialogs are open,
/// so everything after the first `await` goes through a [ProviderContainer]
/// captured up front instead of [ref].
Future<void> showNotebookOptions(
  BuildContext context,
  WidgetRef ref,
  Notebook notebook, {
  VoidCallback? onDeleted,
}) async {
  final ProviderContainer container = ProviderScope.containerOf(context);
  final NotesRepository repo = container.read(notesRepositoryProvider);
  final ReminderService reminders = container.read(reminderServiceProvider);
  if (notebook.locked && !container.read(unlockedNotebooksProvider).contains(notebook.id)) {
    final bool ok = await authenticateUser(reason: 'Unlock this notebook');
    if (!ok || !context.mounted) {
      return;
    }
    container.read(unlockedNotebooksProvider.notifier).update(
          (Set<String> s) => <String>{...s, notebook.id},
        );
  }
  if (!context.mounted) {
    return;
  }
  final _NotebookAction? action = await showVarnaSheet<_NotebookAction>(
    context,
    builder: (BuildContext sheetContext) {
      void pick(_NotebookAction a) => Navigator.of(sheetContext).pop(a);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SheetTitle(
            notebook.title.trim().isEmpty ? 'Untitled' : notebook.title,
            subtitle: 'Notebook options',
          ),
          SheetAction(
            icon: Icons.edit_outlined,
            label: 'Rename',
            onTap: () => pick(_NotebookAction.rename),
          ),
          SheetAction(
            icon: Icons.palette_outlined,
            label: 'Change colour',
            onTap: () => pick(_NotebookAction.colour),
          ),
          SheetAction(
            icon: notebook.locked ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
            label: notebook.locked ? 'Remove lock' : 'Lock notebook',
            subtitle: notebook.locked
                ? null
                : 'Ask for fingerprint, face or passcode to open it',
            onTap: () => pick(_NotebookAction.lock),
          ),
          SheetAction(
            icon: Icons.delete_outline_rounded,
            label: 'Delete notebook',
            destructive: true,
            onTap: () => pick(_NotebookAction.delete),
          ),
        ],
      );
    },
  );
  if (action == null || !context.mounted) {
    return;
  }
  Future<void> save(Notebook updated) async {
    await repo.updateNotebook(updated);
  }

  switch (action) {
    case _NotebookAction.rename:
      final NotebookDraft? renamed = await showNotebookDialog(
        context,
        heading: 'Rename notebook',
        confirmLabel: 'Save',
        initialTitle: notebook.title,
        initialColor: notebook.colorIndex,
        askColor: false,
      );
      if (renamed != null) {
        await save(notebook.copyWith(title: renamed.title));
      }
    case _NotebookAction.colour:
      final NotebookDraft? recoloured = await showNotebookDialog(
        context,
        heading: 'Notebook colour',
        confirmLabel: 'Save',
        initialTitle: notebook.title,
        initialColor: notebook.colorIndex,
        askTitle: false,
      );
      if (recoloured != null) {
        await save(notebook.copyWith(colorIndex: recoloured.colorIndex));
      }
    case _NotebookAction.lock:
      await save(notebook.copyWith(locked: !notebook.locked));
      if (!notebook.locked) {
        container.read(unlockedNotebooksProvider.notifier).update(
              (Set<String> s) => <String>{...s, notebook.id},
            );
      }
    case _NotebookAction.delete:
      final List<NoteCard> cards = await repo.listCards(notebook.id);
      final int count = cards.length;
      if (!context.mounted) {
        return;
      }
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) {
          final VarnaColors c = VarnaColors.of(dialogContext);
          return AlertDialog(
            backgroundColor: c.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Text('Delete this notebook?', style: displayStyle(dialogContext, 22)),
            content: Text(
              count == 0
                  ? 'The notebook will be removed from all your devices.'
                  : 'The notebook and its ${pluralize(count, 'card')} will be '
                      'removed from all your devices. This cannot be undone.',
              style: bodyStyle(dialogContext, 15),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: c.danger),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Delete'),
              ),
            ],
          );
        },
      );
      if (confirmed == true) {
        await repo.deleteNotebook(notebook.id);
        // The cards are gone, so their reminders must not fire.
        for (final NoteCard card in cards) {
          try {
            await reminders.cancel(card.id);
          } catch (_) {
            // A leftover notification is harmless.
          }
        }
        if (container.read(lastNotebookIdProvider) == notebook.id) {
          container.read(lastNotebookIdProvider.notifier).state = null;
        }
        onDeleted?.call();
      }
  }
}

enum _NotebookAction { rename, colour, lock, delete }
