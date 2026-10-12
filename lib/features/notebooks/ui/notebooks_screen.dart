import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/theme/varna_colors.dart';
import '../../../shared/app_state.dart';
import '../../../shared/auth_gate.dart';
import '../../../shared/widgets/centered_column.dart';
import '../../../shared/widgets/dashed_border.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/notebook_cover.dart';
import '../../../shared/widgets/status_chip.dart';
import '../../../shared/widgets/tokens.dart';
import '../../sync/logic/sync_status.dart';
import 'notebook_dialogs.dart';

const BorderRadius _coverRadius = BorderRadius.only(
  topLeft: Radius.circular(8),
  bottomLeft: Radius.circular(8),
  topRight: Radius.circular(20),
  bottomRight: Radius.circular(20),
);

/// The home tab: a grid of notebook covers.
class NotebooksScreen extends ConsumerWidget {
  const NotebooksScreen({super.key});

  Future<void> _open(BuildContext context, WidgetRef ref, Notebook nb) async {
    final GoRouter router = GoRouter.of(context);
    if (nb.locked && !ref.read(unlockedNotebooksProvider).contains(nb.id)) {
      final bool ok = await authenticateUser(reason: 'Unlock ${nb.title}');
      if (!ok) {
        return;
      }
      ref.read(unlockedNotebooksProvider.notifier).update(
            (Set<String> s) => <String>{...s, nb.id},
          );
    }
    await router.push<void>('/notebook/${nb.id}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final VarnaColors c = VarnaColors.of(context);
    final AsyncValue<List<Notebook>> notebooks = ref.watch(notebooksProvider);

    Widget body;
    if (notebooks.hasError && !notebooks.hasValue) {
      body = Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Text(
          'Could not load your notebooks.',
          textAlign: TextAlign.center,
          style: bodyStyle(context, 15, color: c.muted),
        ),
      );
    } else if (!notebooks.hasValue) {
      body = const Padding(
        padding: EdgeInsets.only(top: 60),
        child: Center(child: CircularProgressIndicator()),
      );
    } else {
      final List<Notebook> list = notebooks.requireValue;
      if (list.isEmpty) {
        body = Padding(
          padding: const EdgeInsets.only(top: 32),
          child: EmptyState(
            title: 'Start with a notebook',
            message: 'A notebook keeps related cards together, like Travel, '
                'Work or Recipes.',
            actionLabel: 'Create a notebook',
            onAction: () => unawaited(createNotebookFlow(context, ref)),
          ),
        );
      } else {
        final List<Widget> tiles = <Widget>[
          for (final Notebook nb in list)
            _CoverWithCount(
              notebook: nb,
              onTap: () => unawaited(_open(context, ref, nb)),
              onLongPress: () => unawaited(showNotebookOptions(context, ref, nb)),
            ),
          _NewNotebookTile(
            onTap: () => unawaited(createNotebookFlow(context, ref)),
          ),
        ];
        body = Column(
          children: <Widget>[
            for (int i = 0; i < tiles.length; i += 2)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(child: tiles[i]),
                      const SizedBox(width: 16),
                      Expanded(
                        child: i + 1 < tiles.length
                            ? tiles[i + 1]
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      }
    }

    return SafeArea(
      bottom: false,
      child: CenteredColumn(
        child: RefreshIndicator(
          onRefresh: () async {
            await ref.read(syncControllerProvider).syncNow();
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 130),
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        'Notebooks',
                        style: displayStyle(context, 34, letterSpacing: -0.8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const _SyncChip(),
                ],
              ),
              const SizedBox(height: 14),
              Material(
                color: c.surface,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => unawaited(context.push<void>('/search')),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: <Widget>[
                          Icon(Icons.search_rounded, size: 22, color: c.muted),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Search cards, scans and voice',
                              style: bodyStyle(context, 16, color: c.muted),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              body,
            ],
          ),
        ),
      ),
    );
  }
}

class _SyncChip extends ConsumerWidget {
  const _SyncChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SyncStatus status =
        ref.watch(syncStatusProvider).valueOrNull ?? const SyncIdle();
    final bool connected =
        ref.watch(settingsProvider).valueOrNull?.syncProvider != null;
    return StatusChip(
      status: status,
      connected: connected,
      onTap: () => unawaited(context.push<void>('/settings/sync')),
    );
  }
}

class _CoverWithCount extends ConsumerWidget {
  const _CoverWithCount({
    required this.notebook,
    required this.onTap,
    required this.onLongPress,
  });

  final Notebook notebook;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int count = ref.watch(cardsProvider(notebook.id)).valueOrNull?.length ?? 0;
    return NotebookCover(
      notebook: notebook,
      cardCount: count,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

class _NewNotebookTile extends StatelessWidget {
  const _NewNotebookTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final VarnaColors c = VarnaColors.of(context);
    return Semantics(
      button: true,
      child: DashedBorder(
        color: VarnaExtras.handle,
        borderRadius: _coverRadius,
        child: Material(
          color: Colors.transparent,
          borderRadius: _coverRadius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 120),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '+ New notebook',
                    textAlign: TextAlign.center,
                    style: bodyStyle(context, 15, weight: FontWeight.w600, color: c.ink),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
