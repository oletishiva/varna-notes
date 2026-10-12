import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app_config.dart';
import '../../../core/data/notes_repository.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/services/reminder_service.dart';
import '../../../core/services/usage_limits.dart';
import '../../../core/theme/varna_colors.dart';
import '../../cards/ui/widgets/card_actions.dart';
import '../../cards/ui/widgets/card_saver.dart';
import '../../cards/ui/widgets/format_utils.dart';
import '../../cards/ui/widgets/ui_kit.dart';
import '../logic/renewals_logic.dart';
import 'renewal_actions.dart';

/// The Papers tab: what is due soon, what is coming up, and folders.
///
/// Free users see their papers list; reminders are a Plus feature, so they
/// get an upsell line instead.
class PapersScreen extends ConsumerStatefulWidget {
  const PapersScreen({super.key});

  @override
  ConsumerState<PapersScreen> createState() => _PapersScreenState();
}

class _PapersScreenState extends ConsumerState<PapersScreen> {
  String? _folder;
  bool _busy = false;

  Future<void> _scanPaper() async {
    if (_busy) {
      return;
    }
    final NotesRepository repo = ref.read(notesRepositoryProvider);
    final UsageLimits limits = ref.read(usageLimitsProvider);
    setState(() => _busy = true);
    try {
      final List<Notebook> notebooks = await repo.listNotebooks();
      Notebook? target;
      for (final Notebook n in notebooks) {
        if (n.title.trim().toLowerCase() == 'papers') {
          target = n;
          break;
        }
      }
      if (target == null) {
        final LimitCheck check = await limits.canCreateNotebook();
        if (!mounted) {
          return;
        }
        if (!check.allowed) {
          await _showLimitDialog(check.message);
          return;
        }
        target = await repo.createNotebook(title: 'Papers', colorIndex: 3);
      }
      if (!mounted) {
        return;
      }
      unawaited(context.push('/scan/${target.id}'));
    } catch (_) {
      if (mounted) {
        showInfo(context, 'Could not open the scanner. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _showLimitDialog(String message) async {
    final bool? upgrade = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Notebook limit reached'),
          content: Text(
            '$message\n\nScans are kept in a notebook called "Papers".',
          ),
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

  Future<void> _markRenewed(RenewalItem item) async {
    final NotesRepository repo = ref.read(notesRepositoryProvider);
    final ReminderService reminders = ref.read(reminderServiceProvider);
    final bool isPlus = ref.read(isPlusProvider).value ?? false;
    final DateTime now = DateTime.now();
    final DateTime old = item.dueDate;
    final DateTime firstDate = kRenewalPickerFirstDate;
    final DateTime lastDate = DateTime(now.year + 30, 12, 31);
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: clampPickerDate(
        DateTime(old.year + 1, old.month, old.day),
        firstDate,
        lastDate,
      ),
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: 'New renewal date',
    );
    if (picked == null || !mounted) {
      return;
    }
    final CardSaver saver = CardSaver(repo, item.card.id);
    // The old reminder belongs to the old date.
    await reminders.cancel(item.card.id);
    await saver.update((NoteCard c) => c.copyWith(reminderAt: null));
    final RenewalReminderResult result = await saveRenewalDate(
      saver: saver,
      card: item.card,
      expiry: picked,
      remind: true,
      isPlus: isPlus,
      reminders: reminders,
    );
    if (!mounted) {
      return;
    }
    final DateTime date = DateTime.utc(picked.year, picked.month, picked.day);
    showInfo(
      context,
      describeRenewalResult(result, date) ??
          'Marked renewed. Next date: ${formatDate(date)}.',
    );
  }

  Future<void> _removeDate(RenewalItem item) async {
    final CardSaver saver =
        CardSaver(ref.read(notesRepositoryProvider), item.card.id);
    final ReminderService reminders = ref.read(reminderServiceProvider);
    await saver.update(
      (NoteCard c) => c.copyWith(expiryDate: null, reminderAt: null),
    );
    // The reminder belonged to the date that was just removed.
    try {
      await reminders.cancel(item.card.id);
    } catch (_) {
      // A leftover notification is harmless.
    }
  }

  /// The most urgent item that is overdue or due within 30 days, if any.
  RenewalItem? _firstDueSoon(List<RenewalItem> items) {
    for (final RenewalItem i in items) {
      if (i.urgency != RenewalUrgency.later) {
        return i;
      }
    }
    return null;
  }

  void _open(RenewalItem item) {
    unawaited(context.push('/card/${item.card.id}'));
  }

  @override
  Widget build(BuildContext context) {
    final VarnaColors colors = VarnaColors.of(context);
    final AsyncValue<List<RenewalItem>> items =
        ref.watch(renewalItemsProvider);
    final bool isPlus = ref.watch(isPlusProvider).value ?? false;
    final bool remindersWork = ref.watch(reminderServiceProvider).isSupported;

    return Scaffold(
      backgroundColor: colors.ground,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: items.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (Object e, StackTrace s) => _body(
                      context,
                      const <RenewalItem>[],
                      isPlus,
                      remindersWork,
                    ),
                    data: (List<RenewalItem> list) =>
                        _body(context, list, isPlus, remindersWork),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(88, 56),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    onPressed: _busy ? null : () => unawaited(_scanPaper()),
                    icon: const Icon(Icons.document_scanner_outlined, size: 22),
                    label: const Text('Scan a paper'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    List<RenewalItem> all,
    bool isPlus,
    bool remindersWork,
  ) {
    final VarnaColors colors = VarnaColors.of(context);
    final Map<String, List<RenewalItem>> byFolder =
        RenewalsLogic.groupByFolder(all);
    final String? selected = _folder;
    final List<RenewalItem> shown = selected == null
        ? all
        : all.where((RenewalItem i) => i.folder == selected).toList();

    final RenewalItem? hero = _firstDueSoon(shown);
    final List<RenewalItem> rest =
        shown.where((RenewalItem i) => i != hero).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      children: <Widget>[
        Text('Papers', style: displayStyle(context, 32)),
        const SizedBox(height: 6),
        Text(
          'Scan a bill, policy or warranty. ${AppConfig.appName} reads the '
          'date and reminds you before it runs out.',
          style: bodyStyle(context, 15, color: colors.muted, height: 1.4),
        ),
        const SizedBox(height: 18),
        if (all.isEmpty)
          _EmptyPapers(onScan: _busy ? null : () => unawaited(_scanPaper()))
        else ...<Widget>[
          if (hero != null)
            _HeroCard(
              item: hero,
              onOpen: () => _open(hero),
              onRenewed: () => unawaited(_markRenewed(hero)),
            ),
          if (rest.isNotEmpty) ...<Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
              child: Text(
                hero == null ? 'Your papers' : 'Coming up',
                style: bodyStyle(
                  context,
                  13,
                  weight: FontWeight.w700,
                  color: colors.muted,
                ),
              ),
            ),
            Material(
              color: colors.surface,
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: <Widget>[
                  for (int i = 0; i < rest.length; i++)
                    _PaperRow(
                      item: rest[i],
                      last: i == rest.length - 1,
                      onOpen: () => _open(rest[i]),
                      onRenewed: () => unawaited(_markRenewed(rest[i])),
                      onRemoveDate: () => unawaited(_removeDate(rest[i])),
                    ),
                ],
              ),
            ),
          ] else if (hero == null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'No papers in this folder.',
                style: bodyStyle(context, 15, color: colors.muted),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
            child: Text(
              'Folders',
              style: bodyStyle(
                context,
                13,
                weight: FontWeight.w700,
                color: colors.muted,
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilterPill(
                label: 'All ${all.length}',
                selected: selected == null,
                onTap: () => setState(() => _folder = null),
              ),
              for (final MapEntry<String, List<RenewalItem>> entry
                  in byFolder.entries)
                if (entry.value.isNotEmpty || entry.key == selected)
                  FilterPill(
                    label: '${entry.key} ${entry.value.length}',
                    selected: entry.key == selected,
                    onTap: () => setState(() => _folder = entry.key),
                  ),
            ],
          ),
        ],
        const SizedBox(height: 22),
        _ReminderNote(
          isPlus: isPlus,
          remindersWork: remindersWork,
          onUpgrade: () => unawaited(context.push('/paywall')),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.item,
    required this.onOpen,
    required this.onRenewed,
  });

  final RenewalItem item;
  final VoidCallback onOpen;
  final VoidCallback onRenewed;

  @override
  Widget build(BuildContext context) {
    final VarnaColors colors = VarnaColors.of(context);
    final NoteCard card = item.card;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.cardColor(card.colorIndex),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(item.label, style: bodyStyle(context, 13, weight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(displayTitle(card), style: displayStyle(context, 22)),
          const SizedBox(height: 4),
          Text(
            'Expires ${formatDate(item.dueDate)}, ${item.folder}',
            style: bodyStyle(context, 14),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 46),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: onOpen,
                  child: const Text('Open', textAlign: TextAlign.center),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 46),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    side: BorderSide(color: colors.ink, width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: onRenewed,
                  child: const Text('Mark renewed', textAlign: TextAlign.center),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaperRow extends StatelessWidget {
  const _PaperRow({
    required this.item,
    required this.last,
    required this.onOpen,
    required this.onRenewed,
    required this.onRemoveDate,
  });

  final RenewalItem item;
  final bool last;
  final VoidCallback onOpen;
  final VoidCallback onRenewed;
  final VoidCallback onRemoveDate;

  @override
  Widget build(BuildContext context) {
    final VarnaColors colors = VarnaColors.of(context);
    final NoteCard card = item.card;
    final String day = DateFormat('dd').format(item.dueDate);
    final String month = DateFormat('MMM').format(item.dueDate).toUpperCase();
    return DecoratedBox(
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: colors.hairline)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: InkWell(
              onTap: onOpen,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 68),
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: colors.cardColor(card.colorIndex),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Text(
                              day,
                              style: bodyStyle(
                                context,
                                16,
                                weight: FontWeight.w700,
                                height: 1,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              month,
                              style: bodyStyle(
                                context,
                                10,
                                weight: FontWeight.w700,
                                height: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              displayTitle(card),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: bodyStyle(
                                context,
                                16,
                                weight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${item.folder}, ${item.label.toLowerCase()}',
                              style: bodyStyle(
                                context,
                                13,
                                color: colors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Paper options',
            icon: Icon(Icons.more_vert, color: colors.muted),
            onSelected: (String value) {
              switch (value) {
                case 'open':
                  onOpen();
                case 'renewed':
                  onRenewed();
                case 'remove':
                  onRemoveDate();
              }
            },
            itemBuilder: (BuildContext context) =>
                const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(value: 'open', child: Text('Open')),
              PopupMenuItem<String>(
                value: 'renewed',
                child: Text('Mark renewed'),
              ),
              PopupMenuItem<String>(
                value: 'remove',
                child: Text('Remove date'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyPapers extends StatelessWidget {
  const _EmptyPapers({required this.onScan});

  final VoidCallback? onScan;

  @override
  Widget build(BuildContext context) {
    final VarnaColors colors = VarnaColors.of(context);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: <Widget>[
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: colors.cardColor(0),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.description_outlined, size: 30, color: colors.ink),
          ),
          const SizedBox(height: 14),
          Text(
            'No papers yet',
            textAlign: TextAlign.center,
            style: displayStyle(context, 22),
          ),
          const SizedBox(height: 6),
          Text(
            'When you scan a paper that has an expiry or due date, it appears '
            'here with how many days are left.',
            textAlign: TextAlign.center,
            style: bodyStyle(context, 15, color: colors.muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: onScan,
            child: const Text('Scan your first paper'),
          ),
        ],
      ),
    );
  }
}

class _ReminderNote extends StatelessWidget {
  const _ReminderNote({
    required this.isPlus,
    required this.remindersWork,
    required this.onUpgrade,
  });

  final bool isPlus;
  final bool remindersWork;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final VarnaColors colors = VarnaColors.of(context);
    final String text;
    if (!isPlus) {
      text = 'Your papers stay here for free. Renewal reminders, a '
          'notification $kRenewalLeadDays days before each date, are part of '
          '${AppConfig.appName} Plus.';
    } else if (!remindersWork) {
      text = 'Renewal reminders are included in your plan. They work in the '
          '${AppConfig.appName} mobile app.';
    } else {
      text = 'Reminders are on: you get a notification $kRenewalLeadDays days '
          'before each date.';
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                isPlus
                    ? Icons.notifications_active_outlined
                    : Icons.lock_outline,
                size: 20,
                color: colors.ink,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: bodyStyle(context, 14, height: 1.4),
                ),
              ),
            ],
          ),
          if (!isPlus)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onUpgrade,
                child: Text('See ${AppConfig.appName} Plus'),
              ),
            ),
        ],
      ),
    );
  }
}
