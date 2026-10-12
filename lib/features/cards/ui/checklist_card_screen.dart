import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/data/notes_repository.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/services/reminder_service.dart';
import '../../../core/theme/varna_colors.dart';
import 'widgets/card_actions.dart';
import 'widgets/card_saver.dart';
import 'widgets/card_title_field.dart';
import 'widgets/card_unavailable.dart';
import 'widgets/color_dots.dart';
import 'widgets/format_utils.dart';
import 'widgets/tinted_card_scaffold.dart';
import 'widgets/ui_kit.dart';

/// Editor for checklist cards: progress bar, open items (long-press to drag,
/// swipe to delete with undo), an "Add an item" row and a "Done" section.
class ChecklistCardScreen extends ConsumerWidget {
  const ChecklistCardScreen({super.key, required this.cardId});

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
        return _ChecklistEditor(card: value);
      },
    );
  }
}

class _ChecklistEditor extends ConsumerStatefulWidget {
  const _ChecklistEditor({required this.card});

  final NoteCard card;

  @override
  ConsumerState<_ChecklistEditor> createState() => _ChecklistEditorState();
}

class _ChecklistEditorState extends ConsumerState<_ChecklistEditor> {
  late final NotesRepository _repo;
  late final ReminderService _reminders;
  late final CardSaver _saver;
  late final Autosaver _autosaver;
  late final TextEditingController _title;
  final TextEditingController _newItem = TextEditingController();
  final FocusNode _titleFocus = FocusNode();
  final FocusNode _newItemFocus = FocusNode();

  /// The list the screen shows. Changed immediately by every action (so
  /// dragging and swiping feel instant) and then written to the repository.
  late List<ChecklistItem> _items;
  int _writes = 0;
  bool _deleted = false;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(notesRepositoryProvider);
    _reminders = ref.read(reminderServiceProvider);
    _saver = CardSaver(_repo, widget.card.id);
    _items = List<ChecklistItem>.of(widget.card.items);
    _title = TextEditingController(text: widget.card.title);
    _autosaver = Autosaver(onSave: _saveTitle);
  }

  Future<void> _saveTitle() async {
    final String title = _title.text;
    await _saver.update((NoteCard c) {
      return c.title == title ? c : c.copyWith(title: title);
    });
  }

  @override
  void didUpdateWidget(_ChecklistEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_writes == 0 && !listEquals(_items, widget.card.items)) {
      _items = List<ChecklistItem>.of(widget.card.items);
    }
    final bool editingTitle = _autosaver.hasPendingChanges ||
        _autosaver.isSaving ||
        _titleFocus.hasFocus;
    if (!editingTitle && _title.text != widget.card.title) {
      _title.text = widget.card.title;
    }
  }

  @override
  void dispose() {
    if (!_deleted) {
      _autosaver.dispose();
    }
    _title.dispose();
    _newItem.dispose();
    _titleFocus.dispose();
    _newItemFocus.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ item actions

  Future<void> _persistItems() async {
    final List<ChecklistItem> snapshot = List<ChecklistItem>.of(_items);
    _writes++;
    try {
      await _saver.update((NoteCard c) => c.copyWith(items: snapshot));
    } finally {
      _writes--;
    }
  }

  void _toggle(ChecklistItem item, bool done) {
    setState(() {
      _items = <ChecklistItem>[
        for (final ChecklistItem i in _items)
          if (i.id == item.id) i.copyWith(done: done) else i,
      ];
    });
    unawaited(_persistItems());
  }

  void _addItem(String raw) {
    final String text = raw.trim();
    if (text.isEmpty) {
      return;
    }
    final ChecklistItem item =
        ChecklistItem(id: const Uuid().v4(), text: text);
    setState(() {
      final List<ChecklistItem> open =
          _items.where((ChecklistItem i) => !i.done).toList();
      final List<ChecklistItem> done =
          _items.where((ChecklistItem i) => i.done).toList();
      _items = <ChecklistItem>[...open, item, ...done];
    });
    _newItem.clear();
    _newItemFocus.requestFocus();
    unawaited(_persistItems());
  }

  void _reorder(int oldIndex, int newIndex) {
    final List<ChecklistItem> open =
        _items.where((ChecklistItem i) => !i.done).toList();
    final List<ChecklistItem> done =
        _items.where((ChecklistItem i) => i.done).toList();
    final int target = newIndex;
    if (oldIndex < 0 || oldIndex >= open.length) {
      return;
    }
    final ChecklistItem moved = open.removeAt(oldIndex);
    open.insert(target.clamp(0, open.length).toInt(), moved);
    setState(() => _items = <ChecklistItem>[...open, ...done]);
    unawaited(_persistItems());
  }

  void _delete(ChecklistItem item) {
    final int index = _items.indexWhere((ChecklistItem i) => i.id == item.id);
    if (index < 0) {
      return;
    }
    setState(() {
      _items = <ChecklistItem>[
        for (final ChecklistItem i in _items)
          if (i.id != item.id) i,
      ];
    });
    unawaited(_persistItems());
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Deleted "${item.text}"'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            if (!mounted) {
              return;
            }
            setState(() {
              final List<ChecklistItem> next = List<ChecklistItem>.of(_items);
              next.insert(index.clamp(0, next.length).toInt(), item);
              _items = next;
            });
            unawaited(_persistItems());
          },
        ),
      ),
    );
  }

  Future<void> _edit(ChecklistItem item) async {
    final String? text = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => _EditItemDialog(text: item.text),
    );
    if (text == null || !mounted) {
      return;
    }
    final String trimmed = text.trim();
    if (trimmed.isEmpty || trimmed == item.text) {
      return;
    }
    setState(() {
      _items = <ChecklistItem>[
        for (final ChecklistItem i in _items)
          if (i.id == item.id) i.copyWith(text: trimmed) else i,
      ];
    });
    unawaited(_persistItems());
  }

  void _clearDone() {
    setState(() {
      _items = _items.where((ChecklistItem i) => !i.done).toList();
    });
    unawaited(_persistItems());
  }

  // -------------------------------------------------------------- card level

  Future<void> _goBack() async {
    await _autosaver.flush();
    if (!mounted) {
      return;
    }
    leaveScreen(context);
  }

  Future<void> _deleteCard() async {
    final bool ok = await confirmDelete(
      context,
      title: 'Delete this checklist?',
    );
    if (!ok || !mounted) {
      return;
    }
    _deleted = true;
    final String id = widget.card.id;
    leaveScreen(context);
    await _reminders.cancel(id);
    await _repo.deleteCard(id);
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

  // ------------------------------------------------------------------- build

  Widget _itemRow(
    BuildContext context,
    ChecklistItem item, {
    required bool done,
    required bool last,
    int? reorderIndex,
  }) {
    final VarnaColors colors = VarnaColors.of(context);
    final Color lineColor = colors.ink.withValues(alpha: 0.15);
    final TextStyle textStyle = bodyStyle(
      context,
      18,
      color: done ? colors.ink.withValues(alpha: 0.65) : colors.ink,
    ).copyWith(
      decoration: done ? TextDecoration.lineThrough : TextDecoration.none,
    );

    Widget row = Container(
      constraints: BoxConstraints(minHeight: done ? 50 : 54),
      decoration: BoxDecoration(
        color: colors.cardColor(widget.card.colorIndex),
        border: last ? null : Border(bottom: BorderSide(color: lineColor)),
      ),
      child: Row(
        children: <Widget>[
          Semantics(
            label: item.text,
            child: Checkbox(
              value: item.done,
              activeColor: colors.ink,
              checkColor: Colors.white,
              side: BorderSide(color: colors.ink, width: 2),
              onChanged: (bool? value) => _toggle(item, value ?? false),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: InkWell(
              onTap: () => unawaited(_edit(item)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(item.text, style: textStyle),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (reorderIndex != null) {
      row = ReorderableDelayedDragStartListener(
        index: reorderIndex,
        child: row,
      );
    }

    return Dismissible(
      key: ValueKey<String>('item-${item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: colors.danger,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (DismissDirection direction) => _delete(item),
      child: row,
    );
  }

  @override
  Widget build(BuildContext context) {
    final VarnaColors colors = VarnaColors.of(context);
    final NoteCard card = widget.card;
    final AsyncValue<AppSettings> settings = ref.watch(settingsProvider);
    final SyncProviderId? provider = settings.value?.syncProvider;

    final List<ChecklistItem> open =
        _items.where((ChecklistItem i) => !i.done).toList();
    final List<ChecklistItem> done =
        _items.where((ChecklistItem i) => i.done).toList();
    final int total = _items.length;
    final double fraction = total == 0 ? 0 : done.length / total;

    final Widget progress = Row(
      children: <Widget>[
        Expanded(
          child: Semantics(
            label: '${done.length} of $total done',
            child: ExcludeSemantics(
              child: Container(
                height: 8,
                decoration: BoxDecoration(
                  color: colors.ink.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: fraction,
                  child: Container(
                    decoration: BoxDecoration(
                      color: colors.ink,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          total == 0 ? 'No items yet' : '${done.length} of $total',
          style: bodyStyle(context, 14, weight: FontWeight.w700),
        ),
      ],
    );

    final Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 22),
        CardTitleField(
          controller: _title,
          focusNode: _titleFocus,
          hintText: 'Checklist title',
          onChanged: (_) => _autosaver.markChanged(),
          onSubmitted: (_) => _newItemFocus.requestFocus(),
        ),
        const SizedBox(height: 10),
        progress,
        const SizedBox(height: 18),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: _reorder,
          children: <Widget>[
            for (int i = 0; i < open.length; i++)
              _itemRow(
                context,
                open[i],
                done: false,
                last: false,
                reorderIndex: i,
              ),
          ],
        ),
        Container(
          constraints: const BoxConstraints(minHeight: 54),
          padding: const EdgeInsets.only(left: 38),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Semantics(
                  textField: true,
                  label: 'Add an item',
                  child: TextField(
                    controller: _newItem,
                    focusNode: _newItemFocus,
                    style: bodyStyle(context, 18, color: colors.ink),
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.done,
                    cursorColor: colors.ink,
                    decoration: InputDecoration(
                      hintText: 'Add an item',
                      hintStyle: bodyStyle(
                        context,
                        18,
                        color: colors.ink.withValues(alpha: 0.5),
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onSubmitted: _addItem,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Add item',
                onPressed: () => _addItem(_newItem.text),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ),
        if (done.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          Text('Done', style: bodyStyle(context, 13, weight: FontWeight.w700)),
          for (int i = 0; i < done.length; i++)
            _itemRow(
              context,
              done[i],
              done: true,
              last: true,
            ),
        ],
        const SizedBox(height: 24),
      ],
    );

    final DateTime? reminderAt = card.reminderAt;
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
        FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size(88, 54),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          onPressed: () => unawaited(_setReminder()),
          icon: Icon(
            reminderAt == null
                ? Icons.notifications_none
                : Icons.notifications_active_outlined,
            size: 20,
          ),
          label: Text(
            reminderAt == null
                ? 'Remind me'
                : 'Reminder: ${formatDateTime(reminderAt)}',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
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
      onDelete: () => unawaited(_deleteCard()),
      extraActions: <CardMenuAction>[
        if (done.isNotEmpty)
          CardMenuAction(
            label: 'Clear done items',
            icon: Icons.playlist_remove,
            onSelected: _clearDone,
          ),
      ],
      content: content,
      footer: footer,
    );
  }
}

/// Small dialog to change the text of one item.
class _EditItemDialog extends StatefulWidget {
  const _EditItemDialog({required this.text});

  final String text;

  @override
  State<_EditItemDialog> createState() => _EditItemDialogState();
}

class _EditItemDialogState extends State<_EditItemDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.text);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit item'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        onSubmitted: (String value) => Navigator.of(context).pop(value),
        decoration: const InputDecoration(hintText: 'Item'),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
