import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/attachment_store.dart';
import '../../../core/data/notes_repository.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/theme/varna_colors.dart';
import '../../../shared/app_state.dart';
import '../../../shared/auth_gate.dart';
import '../../../shared/format.dart';
import '../../../shared/nav.dart';
import '../../../shared/widgets/card_tile.dart';
import '../../../shared/widgets/centered_column.dart';
import '../../../shared/widgets/color_swatch_picker.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pill_chips.dart';
import '../../../shared/widgets/round_icon_button.dart';
import '../../../shared/widgets/tokens.dart';
import '../../../shared/widgets/varna_bottom_sheet.dart';
import '../../../shared/widgets/varna_button.dart';
import '../../cards/ui/new_card_sheet.dart';
import '../../sync/logic/sync_status.dart';
import 'notebook_dialogs.dart';

enum _Filter { all, favourites }

/// Inside one notebook: a two column masonry of cards.
class NotebookScreen extends ConsumerStatefulWidget {
  const NotebookScreen({super.key, required this.notebookId});

  final String notebookId;

  @override
  ConsumerState<NotebookScreen> createState() => _NotebookScreenState();
}

class _NotebookScreenState extends ConsumerState<NotebookScreen> {
  _Filter _filter = _Filter.all;
  bool _autoPrompted = false;
  bool _prompting = false;

  Future<void> _unlock() async {
    if (_prompting) {
      return;
    }
    _prompting = true;
    final bool ok = await authenticateUser(reason: 'Unlock this notebook');
    _prompting = false;
    if (!mounted || !ok) {
      return;
    }
    ref.read(unlockedNotebooksProvider.notifier).update(
          (Set<String> s) => <String>{...s, widget.notebookId},
        );
  }

  void _markOpened() {
    if (ref.read(lastNotebookIdProvider) != widget.notebookId) {
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        if (mounted) {
          ref.read(lastNotebookIdProvider.notifier).state = widget.notebookId;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Notebook?> nbAsync = ref.watch(notebookProvider(widget.notebookId));
    final Set<String> unlocked = ref.watch(unlockedNotebooksProvider);
    final VarnaColors c = VarnaColors.of(context);

    Widget content;
    if (nbAsync.hasValue) {
      final Notebook? nb = nbAsync.requireValue;
      if (nb == null) {
        content = _Message(
          title: 'This notebook is gone',
          message: 'It may have been deleted on another device.',
          actionLabel: 'Back to notebooks',
          onAction: () => context.go('/'),
        );
      } else if (nb.locked && !unlocked.contains(nb.id)) {
        if (!_autoPrompted) {
          _autoPrompted = true;
          WidgetsBinding.instance.addPostFrameCallback((Duration _) {
            if (mounted) {
              unawaited(_unlock());
            }
          });
        }
        content = Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: <Widget>[
                  RoundIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Back to notebooks',
                    onPressed: () => goBackOr(context, '/'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: _Message(
                    title: nb.title.trim().isEmpty ? 'Locked notebook' : nb.title,
                    message: 'This notebook is locked. Unlock it with your '
                        'fingerprint, face or passcode.',
                    actionLabel: 'Unlock',
                    onAction: () => unawaited(_unlock()),
                    icon: Icons.lock_outline_rounded,
                  ),
                ),
              ),
            ),
          ],
        );
      } else {
        _markOpened();
        content = _Opened(
          notebook: nb,
          filter: _filter,
          onFilter: (_Filter f) => setState(() => _filter = f),
        );
      }
    } else if (nbAsync.hasError) {
      content = _Message(
        title: 'Could not open this notebook',
        message: 'Please go back and try again.',
        actionLabel: 'Back',
        onAction: () => goBackOr(context, '/'),
      );
    } else {
      content = const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      backgroundColor: c.ground,
      body: SafeArea(child: CenteredColumn(child: content)),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.icon,
  });

  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final VarnaColors c = VarnaColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 40, color: c.ink),
            const SizedBox(height: 16),
          ],
          Text(
            title,
            textAlign: TextAlign.center,
            style: displayStyle(context, 26),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: bodyStyle(context, 15, color: c.muted, height: 1.45),
          ),
          const SizedBox(height: 20),
          VarnaButton(label: actionLabel, onPressed: onAction, expand: false),
        ],
      ),
    );
  }
}

class _Opened extends ConsumerWidget {
  const _Opened({
    required this.notebook,
    required this.filter,
    required this.onFilter,
  });

  final Notebook notebook;
  final _Filter filter;
  final ValueChanged<_Filter> onFilter;

  /// Rough height of a card so the two columns end up about equally tall.
  double _weight(NoteCard card) {
    switch (card.type) {
      case CardType.text:
        return 70 + (card.body.length > 220 ? 220 : card.body.length) / 2.2;
      case CardType.checklist:
        return 70 + 26.0 * (card.items.length > 4 ? 4 : card.items.length);
      case CardType.voice:
        return 110;
      case CardType.photo:
        return 190;
      case CardType.scan:
        return 150;
      case CardType.link:
        return 90;
    }
  }

  String _subtitle(WidgetRef ref, int count) {
    final String base = pluralize(count, 'card');
    final SyncStatus? status = ref.watch(syncStatusProvider).valueOrNull;
    final bool connected =
        ref.watch(settingsProvider).valueOrNull?.syncProvider != null;
    if (!connected || status == null) {
      return base;
    }
    if (status is SyncSynced) {
      return '$base, all backed up';
    }
    if (status is SyncSyncing) {
      return '$base, syncing';
    }
    if (status is SyncConflicts) {
      return '$base, ${status.count} need your choice';
    }
    return base;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final VarnaColors c = VarnaColors.of(context);
    final AsyncValue<List<NoteCard>> cardsAsync = ref.watch(cardsProvider(notebook.id));
    final List<NoteCard> all = cardsAsync.valueOrNull ?? const <NoteCard>[];
    final bool hasFavourites = all.any((NoteCard x) => x.favourite);
    final _Filter activeFilter = hasFavourites ? filter : _Filter.all;
    final List<NoteCard> shown = activeFilter == _Filter.favourites
        ? all.where((NoteCard x) => x.favourite).toList()
        : all;

    // Split into two columns, always adding to the shorter one.
    final List<Widget> left = <Widget>[];
    final List<Widget> right = <Widget>[];
    double leftHeight = 0;
    double rightHeight = 0;
    for (final NoteCard card in shown) {
      final Widget tile = CardTile(
        key: ValueKey<String>(card.id),
        card: card,
        onTap: () => unawaited(context.push<void>('/card/${card.id}')),
        onLongPress: () => unawaited(_showCardMenu(context, ref, card)),
      );
      if (leftHeight <= rightHeight) {
        left.add(tile);
        leftHeight += _weight(card);
      } else {
        right.add(tile);
        rightHeight += _weight(card);
      }
    }

    Widget column(List<Widget> tiles) => Column(
          children: <Widget>[
            for (int i = 0; i < tiles.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(height: 14),
              tiles[i],
            ],
          ],
        );

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  RoundIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Back to notebooks',
                    onPressed: () => goBackOr(context, '/'),
                  ),
                  RoundIconButton(
                    icon: Icons.more_horiz_rounded,
                    tooltip: 'Notebook options',
                    onPressed: () => unawaited(
                      showNotebookOptions(
                        context,
                        ref,
                        notebook,
                        onDeleted: () => context.go('/'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Semantics(
                      header: true,
                      child: Text(
                        notebook.title.trim().isEmpty ? 'Untitled' : notebook.title,
                        style: displayStyle(context, 32, letterSpacing: -0.8),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(ref, all.length),
                      style: bodyStyle(context, 14, color: c.muted),
                    ),
                    if (hasFavourites) ...<Widget>[
                      const SizedBox(height: 14),
                      PillChips<_Filter>(
                        options: const <PillOption<_Filter>>[
                          PillOption<_Filter>(_Filter.all, 'All'),
                          PillOption<_Filter>(_Filter.favourites, 'Favourites'),
                        ],
                        selected: activeFilter,
                        onSelected: onFilter,
                      ),
                    ],
                    const SizedBox(height: 18),
                    if (cardsAsync.hasValue && all.isEmpty)
                      EmptyState(
                        title: 'No cards yet',
                        message: 'Add a note, checklist, voice memo, photo or '
                            'scan. Each one gets its own card.',
                        actionLabel: 'Add a card',
                        onAction: () => unawaited(
                          showNewCardSheet(context, notebookId: notebook.id),
                        ),
                      )
                    else if (!cardsAsync.hasValue)
                      const Padding(
                        padding: EdgeInsets.only(top: 40),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(child: column(left)),
                          const SizedBox(width: 14),
                          Expanded(child: column(right)),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        Positioned(
          right: 20,
          bottom: 24,
          child: VarnaFab(
            onPressed: () => unawaited(
              showNewCardSheet(context, notebookId: notebook.id),
            ),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------- card menu

  Future<void> _showCardMenu(
    BuildContext context,
    WidgetRef ref,
    NoteCard card,
  ) async {
    final _CardAction? action = await showVarnaSheet<_CardAction>(
      context,
      builder: (BuildContext sheetContext) {
        void pick(_CardAction a) => Navigator.of(sheetContext).pop(a);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SheetTitle(
              card.title.trim().isEmpty ? 'Card options' : card.title.trim(),
              subtitle: card.title.trim().isEmpty ? null : 'Card options',
            ),
            SheetAction(
              icon: card.favourite ? Icons.star_rounded : Icons.star_outline_rounded,
              label: card.favourite ? 'Remove from favourites' : 'Add to favourites',
              onTap: () => pick(_CardAction.favourite),
            ),
            SheetAction(
              icon: Icons.drive_file_move_outline,
              label: 'Move to another notebook',
              onTap: () => pick(_CardAction.move),
            ),
            SheetAction(
              icon: Icons.palette_outlined,
              label: 'Change colour',
              onTap: () => pick(_CardAction.colour),
            ),
            SheetAction(
              icon: Icons.delete_outline_rounded,
              label: 'Delete',
              destructive: true,
              onTap: () => pick(_CardAction.delete),
            ),
          ],
        );
      },
    );
    if (action == null || !context.mounted) {
      return;
    }
    final NotesRepository repo = ref.read(notesRepositoryProvider);
    switch (action) {
      case _CardAction.favourite:
        await repo.updateCard(card.copyWith(favourite: !card.favourite));
      case _CardAction.colour:
        final int? colour = await showVarnaSheet<int>(
          context,
          builder: (BuildContext sheetContext) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SheetTitle('Card colour'),
              ColorSwatchPicker(
                selected: card.colorIndex,
                onChanged: (int i) => Navigator.of(sheetContext).pop(i),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
        if (colour != null) {
          await repo.updateCard(card.copyWith(colorIndex: colour));
        }
      case _CardAction.move:
        await _moveCard(context, ref, card);
      case _CardAction.delete:
        await _deleteCard(context, ref, card);
    }
  }

  Future<void> _moveCard(BuildContext context, WidgetRef ref, NoteCard card) async {
    final List<Notebook> others = (ref.read(notebooksProvider).valueOrNull ?? <Notebook>[])
        .where((Notebook n) => n.id != card.notebookId)
        .toList();
    if (others.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create another notebook first.')),
      );
      return;
    }
    final Notebook? target = await showVarnaSheet<Notebook>(
      context,
      builder: (BuildContext sheetContext) {
        final VarnaColors c = VarnaColors.of(sheetContext);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SheetTitle('Move to'),
            for (final Notebook n in others)
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.of(sheetContext).pop(n),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 52),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: c.cardColor(n.colorIndex),
                            borderRadius: BorderRadius.circular(7),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            n.title.trim().isEmpty ? 'Untitled' : n.title,
                            style: bodyStyle(sheetContext, 16, weight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
    if (target == null) {
      return;
    }
    await ref
        .read(notesRepositoryProvider)
        .updateCard(card.copyWith(notebookId: target.id));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Moved to ${target.title}')),
      );
    }
  }

  /// Soft-deletes the card and offers Undo. The attachment bytes are read
  /// first because deleting a card removes them from the store.
  Future<void> _deleteCard(BuildContext context, WidgetRef ref, NoteCard card) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NotesRepository repo = ref.read(notesRepositoryProvider);
    final AttachmentStore store = ref.read(attachmentStoreProvider);
    final Map<String, Uint8List> saved = <String, Uint8List>{};
    for (final Attachment a in card.attachments) {
      final Uint8List? bytes = await store.read(a.id);
      if (bytes != null) {
        saved[a.id] = bytes;
      }
    }
    try {
      await ref.read(reminderServiceProvider).cancel(card.id);
    } catch (_) {
      // Best effort.
    }
    await repo.deleteCard(card.id);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Card deleted'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Undo',
          textColor: VarnaColors.light.cardColor(0),
          onPressed: () {
            unawaited(() async {
              for (final MapEntry<String, Uint8List> e in saved.entries) {
                await store.save(e.key, e.value);
              }
              await repo.updateCard(card.copyWith(deleted: false));
            }());
          },
        ),
      ),
    );
  }
}

enum _CardAction { favourite, move, colour, delete }
