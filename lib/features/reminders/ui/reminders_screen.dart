import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/theme/varna_colors.dart';
import '../../../shared/format.dart';
import '../../../shared/widgets/centered_column.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/section_label.dart';
import '../../../shared/widgets/tokens.dart';

class _Reminder {
  const _Reminder(this.card, this.notebook);

  final NoteCard card;
  final Notebook notebook;
}

/// Cards with a reminder in the future, grouped by day.
class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final VarnaColors c = VarnaColors.of(context);
    final DateTime now = ref.watch(clockProvider)();
    final AsyncValue<List<Notebook>> notebooks = ref.watch(notebooksProvider);
    final bool supported = ref.watch(reminderServiceProvider).isSupported;

    final List<_Reminder> items = <_Reminder>[];
    bool loading = !notebooks.hasValue;
    for (final Notebook nb in notebooks.valueOrNull ?? const <Notebook>[]) {
      final AsyncValue<List<NoteCard>> cards = ref.watch(cardsProvider(nb.id));
      if (!cards.hasValue) {
        loading = true;
      }
      for (final NoteCard card in cards.valueOrNull ?? const <NoteCard>[]) {
        final DateTime? at = card.reminderAt;
        if (at != null && at.isAfter(now)) {
          items.add(_Reminder(card, nb));
        }
      }
    }
    items.sort(
      (_Reminder a, _Reminder b) => a.card.reminderAt!.compareTo(b.card.reminderAt!),
    );

    final List<Widget> children = <Widget>[
      Semantics(
        header: true,
        child: Text('Reminders', style: displayStyle(context, 34, letterSpacing: -0.8)),
      ),
    ];

    if (loading && items.isEmpty) {
      children.add(
        const Padding(
          padding: EdgeInsets.only(top: 60),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    } else if (items.isEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 32),
          child: EmptyState(
            title: 'Nothing to remember yet',
            message: 'Set a reminder on any card and it will show up here.',
            actionLabel: 'Open my notebooks',
            onAction: () => context.go('/'),
          ),
        ),
      );
    } else {
      if (!supported) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Notifications are not available on this device, so reminders '
              'are only listed here.',
              style: bodyStyle(context, 13, color: c.muted),
            ),
          ),
        );
      }
      DateTime? currentDay;
      for (final _Reminder item in items) {
        final DateTime at = item.card.reminderAt!.toLocal();
        final DateTime day = DateTime(at.year, at.month, at.day);
        if (currentDay != day) {
          currentDay = day;
          children.add(SectionLabel(dayHeading(at, now: now)));
        }
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ReminderRow(item: item),
          ),
        );
      }
    }

    return SafeArea(
      bottom: false,
      child: CenteredColumn(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 130),
          children: children,
        ),
      ),
    );
  }
}

class _ReminderRow extends StatelessWidget {
  const _ReminderRow({required this.item});

  final _Reminder item;

  String _headline() {
    final NoteCard card = item.card;
    if (card.title.trim().isNotEmpty) {
      return card.title.trim();
    }
    if (card.body.trim().isNotEmpty) {
      return card.body.trim();
    }
    if (card.items.isNotEmpty) {
      return card.items.first.text;
    }
    return 'Untitled card';
  }

  @override
  Widget build(BuildContext context) {
    final VarnaColors c = VarnaColors.of(context);
    final NoteCard card = item.card;
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push<void>('/card/${card.id}'),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: <Widget>[
                ExcludeSemantics(
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: c.cardColor(card.colorIndex),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.notifications_none_rounded, size: 22, color: c.ink),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _headline(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: bodyStyle(context, 16, weight: FontWeight.w700, height: 1.25),
                      ),
                      Text(
                        '${clockTime(card.reminderAt!)}, ${item.notebook.title.trim().isEmpty ? 'Untitled' : item.notebook.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: bodyStyle(context, 13, color: c.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
