import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/theme/varna_colors.dart';
import '../../../shared/format.dart';
import '../../../shared/nav.dart';
import '../../../shared/widgets/centered_column.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/round_icon_button.dart';
import '../../../shared/widgets/selectable_card.dart';
import '../../../shared/widgets/tokens.dart';
import '../../../shared/widgets/varna_button.dart';

// ------------------------------------------------------------ text helpers

/// One version of a record as readable text.
String _versionText(SyncConflict conflict, {required bool local}) {
  final bool deleted = local ? conflict.localDeleted : conflict.remoteDeleted;
  if (deleted) {
    return 'This version was deleted.';
  }
  try {
    if (conflict.kind == RecordKind.notebook) {
      final Notebook nb = local ? conflict.localNotebook : conflict.remoteNotebook;
      return '${nb.title.trim().isEmpty ? 'Untitled' : nb.title}'
          '${nb.locked ? '\nLocked' : ''}';
    }
    final NoteCard card = local ? conflict.localCard : conflict.remoteCard;
    final List<String> lines = <String>[];
    if (card.title.trim().isNotEmpty) {
      lines.add(card.title.trim());
    }
    if (card.body.trim().isNotEmpty) {
      lines.add(card.body.trim());
    }
    for (final ChecklistItem item in card.items) {
      lines.add('${item.done ? '[x]' : '[ ]'} ${item.text}');
    }
    if ((card.transcript ?? '').trim().isNotEmpty) {
      lines.add(card.transcript!.trim());
    }
    if (lines.isEmpty) {
      lines.add(
        card.attachments.isEmpty ? 'Empty card' : '${card.type.name} card',
      );
    }
    return lines.join('\n');
  } catch (_) {
    return 'This version could not be read.';
  }
}

/// Splits two texts into (unchanged start, changed middle, unchanged end) by
/// words, so only the differing words get highlighted.
({String head, String mid, String tail}) _splitDiff(String text, String other) {
  final List<String> a = text.split(' ');
  final List<String> b = other.split(' ');
  int start = 0;
  while (start < a.length && start < b.length && a[start] == b[start]) {
    start++;
  }
  int endA = a.length;
  int endB = b.length;
  while (endA > start && endB > start && a[endA - 1] == b[endB - 1]) {
    endA--;
    endB--;
  }
  String join(int from, int to) => a.sublist(from, to).join(' ');
  final String head = start == 0 ? '' : '${join(0, start)} ';
  final String mid = join(start, endA);
  final String tail = endA >= a.length ? '' : ' ${join(endA, a.length)}';
  return (head: head, mid: mid, tail: tail);
}

String _titleOf(SyncConflict conflict) {
  final String t = conflict.localTitle.trim().isNotEmpty
      ? conflict.localTitle.trim()
      : conflict.remoteTitle.trim();
  return t.isEmpty ? 'Untitled' : t;
}

// ------------------------------------------------------------- single page

/// `/conflict/:id`: pick which version of a card (or notebook) to keep.
class ConflictScreen extends ConsumerStatefulWidget {
  const ConflictScreen({super.key, required this.conflictId});

  final String conflictId;

  @override
  ConsumerState<ConflictScreen> createState() => _ConflictScreenState();
}

class _ConflictScreenState extends ConsumerState<ConflictScreen> {
  bool _keepLocal = true;
  bool _busy = false;

  Future<void> _resolve(ConflictResolution resolution) async {
    if (_busy) {
      return;
    }
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final GoRouter router = GoRouter.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(syncControllerProvider).resolveConflict(
            widget.conflictId,
            resolution,
          );
      messenger.showSnackBar(const SnackBar(content: Text('Done. Both copies are in order.')));
      if (router.canPop()) {
        router.pop();
      } else {
        router.go('/settings/sync');
      }
    } on StateError {
      messenger.showSnackBar(
        const SnackBar(content: Text('Connect your cloud first to resolve this.')),
      );
      if (mounted) {
        setState(() => _busy = false);
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not finish: $e')),
      );
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final VarnaColors c = VarnaColors.of(context);
    final AsyncValue<SyncConflict?> found = ref.watch(conflictProvider(widget.conflictId));

    Widget body;
    if (found.hasError) {
      body = Center(
        child: EmptyState(
          title: 'Could not open this',
          message: 'Please go back and try again.',
          actionLabel: 'Back',
          onAction: () => goBackOr(context, '/settings/sync'),
        ),
      );
    } else if (!found.hasValue) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final SyncConflict? conflict = found.requireValue;
      if (conflict == null) {
        body = Center(
          child: SingleChildScrollView(
            child: EmptyState(
              title: 'Already sorted',
              message: 'This conflict has been resolved.',
              actionLabel: 'Back to sync settings',
              onAction: () => goBackOr(context, '/settings/sync'),
            ),
          ),
        );
      } else {
        body = _buildConflict(context, c, conflict);
      }
    }

    return Scaffold(
      body: SafeArea(child: CenteredColumn(child: body)),
    );
  }

  Widget _buildConflict(BuildContext context, VarnaColors c, SyncConflict conflict) {
    final String localText = _versionText(conflict, local: true);
    final String remoteText = _versionText(conflict, local: false);
    final bool isNotebook = conflict.kind == RecordKind.notebook;
    final bool differ = localText != remoteText;

    Widget version({
      required bool local,
      required String label,
      required String text,
      required String other,
    }) {
      final bool selected = _keepLocal == local;
      final Color highlight = selected ? c.surface : c.cardColor(1);
      final ({String head, String mid, String tail}) parts =
          differ ? _splitDiff(text, other) : (head: text, mid: '', tail: '');
      final TextStyle base = bodyStyle(context, 16, height: 1.45);
      return SelectableCard(
        selected: selected,
        radius: 20,
        color: selected ? c.cardColor(0) : c.surface,
        onTap: _busy ? null : () => setState(() => _keepLocal = local),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    label,
                    style: bodyStyle(context, 14, weight: FontWeight.w700),
                  ),
                ),
                SelectionMark(selected: selected),
              ],
            ),
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(
                style: base,
                children: <InlineSpan>[
                  TextSpan(text: parts.head),
                  if (parts.mid.isNotEmpty)
                    TextSpan(
                      text: parts.mid,
                      style: base.copyWith(
                        fontWeight: FontWeight.w700,
                        backgroundColor: highlight,
                      ),
                    ),
                  TextSpan(text: parts.tail),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return CustomScrollView(
      slivers: <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Align(
                  alignment: Alignment.centerLeft,
                  child: RoundIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Back',
                    onPressed: () => goBackOr(context, '/settings/sync'),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Needs your choice',
                  style: bodyStyle(
                    context,
                    14,
                    weight: FontWeight.w700,
                    color: VarnaExtras.warnText,
                  ),
                ),
                const SizedBox(height: 8),
                Semantics(
                  header: true,
                  child: Text(
                    isNotebook
                        ? 'This notebook changed on two devices'
                        : 'This card changed on two devices',
                    style: displayStyle(context, 30, letterSpacing: -0.7, height: 1.1),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Nothing is lost. Both versions of "${_titleOf(conflict)}" are '
                  'safe until you decide.',
                  style: bodyStyle(context, 16, color: c.muted, height: 1.45),
                ),
                const SizedBox(height: 22),
                version(
                  local: true,
                  label: 'This device, ${dayAndTime(conflict.localUpdatedAt)}',
                  text: localText,
                  other: remoteText,
                ),
                const SizedBox(height: 14),
                version(
                  local: false,
                  label: 'Your cloud, ${dayAndTime(conflict.remoteUpdatedAt)}',
                  text: remoteText,
                  other: localText,
                ),
                if (differ) ...<Widget>[
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(Icons.info_outline_rounded, size: 18, color: c.muted),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Only the highlighted words differ. The rest is the '
                            'same on both.',
                            style: bodyStyle(context, 14, color: c.muted),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const Spacer(),
                const SizedBox(height: 20),
                VarnaButton(
                  label: 'Keep the selected version',
                  busy: _busy,
                  onPressed: () => unawaited(
                    _resolve(
                      _keepLocal
                          ? ConflictResolution.keepLocal
                          : ConflictResolution.keepRemote,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                VarnaButton(
                  label: isNotebook
                      ? 'Keep both as separate notebooks'
                      : 'Keep both as separate cards',
                  kind: VarnaButtonKind.secondary,
                  onPressed: _busy
                      ? null
                      : () => unawaited(_resolve(ConflictResolution.keepBoth)),
                ),
                const SizedBox(height: 4),
                VarnaButton(
                  label: 'Decide later',
                  kind: VarnaButtonKind.text,
                  onPressed: _busy ? null : () => goBackOr(context, '/settings/sync'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- list page

/// `/settings/sync/conflicts`: every open conflict.
class ConflictsListScreen extends ConsumerWidget {
  const ConflictsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final VarnaColors c = VarnaColors.of(context);
    final AsyncValue<List<SyncConflict>> listAsync = ref.watch(conflictsProvider);
    final List<SyncConflict> items = listAsync.valueOrNull ?? const <SyncConflict>[];

    Widget body;
    if (!listAsync.hasValue) {
      body = const Padding(
        padding: EdgeInsets.only(top: 60),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (items.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.only(top: 32),
        child: EmptyState(
          title: 'No conflicts',
          message: 'Everything is in step across your devices.',
          actionLabel: 'Back to sync settings',
          onAction: () => goBackOr(context, '/settings/sync'),
        ),
      );
    } else {
      body = Column(
        children: <Widget>[
          for (final SyncConflict item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: c.surface,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => context.push<void>('/conflict/${item.id}'),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 64),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  item.kind == RecordKind.notebook
                                      ? 'Notebook'
                                      : 'Card',
                                  style: bodyStyle(
                                    context,
                                    12,
                                    weight: FontWeight.w700,
                                    color: VarnaExtras.warnText,
                                  ),
                                ),
                                Text(
                                  _titleOf(item),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: bodyStyle(context, 16, weight: FontWeight.w700),
                                ),
                                Text(
                                  'Found ${dayAndTime(item.detectedAt)}',
                                  style: bodyStyle(context, 13, color: c.muted),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: c.muted),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    }

    return Scaffold(
      body: SafeArea(
        child: CenteredColumn(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: <Widget>[
              Row(
                children: <Widget>[
                  RoundIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Back',
                    onPressed: () => goBackOr(context, '/settings/sync'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text('Sync conflicts', style: displayStyle(context, 26)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              body,
            ],
          ),
        ),
      ),
    );
  }
}
