import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app_config.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/services/usage_limits.dart';
import '../../../core/theme/varna_colors.dart';
import '../../../core/theme/varna_theme.dart';
import '../../../shared/format.dart';
import '../../../shared/widgets/tokens.dart';
import '../../../shared/widgets/varna_bottom_sheet.dart';
import '../../../shared/widgets/varna_button.dart';

/// Why the free-limit sheet is shown.
enum UpsellReason {
  notebookLimit,
  scanLimit,
  transcriptLimit;

  /// Maps the core's [LimitReason].
  static UpsellReason fromLimit(LimitReason reason) {
    switch (reason) {
      case LimitReason.notebookLimit:
        return UpsellReason.notebookLimit;
      case LimitReason.scanLimit:
        return UpsellReason.scanLimit;
      case LimitReason.transcriptLimit:
        return UpsellReason.transcriptLimit;
    }
  }
}

/// Shows the "free limit reached" bottom sheet. If the user taps the Plus
/// button the sheet closes and the paywall opens.
Future<void> showUpsellSheet(
  BuildContext context, {
  required UpsellReason reason,
}) async {
  final GoRouter router = GoRouter.of(context);
  final bool? openPaywall = await showVarnaSheet<bool>(
    context,
    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
    builder: (BuildContext sheetContext) => _UpsellBody(reason: reason),
  );
  if (openPaywall == true) {
    await router.push<void>('/paywall');
  }
}

class _UpsellBody extends ConsumerWidget {
  const _UpsellBody({required this.reason});

  final UpsellReason reason;

  int get _limit {
    switch (reason) {
      case UpsellReason.notebookLimit:
        return AppConfig.freeNotebookLimit;
      case UpsellReason.scanLimit:
        return AppConfig.freeScansPerMonth;
      case UpsellReason.transcriptLimit:
        return AppConfig.freeTranscriptsPerMonth;
    }
  }

  String get _kicker {
    switch (reason) {
      case UpsellReason.notebookLimit:
        return 'Free notebooks used up';
      case UpsellReason.scanLimit:
        return 'Free scans used up';
      case UpsellReason.transcriptLimit:
        return 'Your recording is saved';
    }
  }

  String get _title {
    switch (reason) {
      case UpsellReason.notebookLimit:
        return 'You have used all $_limit free notebooks';
      case UpsellReason.scanLimit:
        return "You have used this month's $_limit free scans";
      case UpsellReason.transcriptLimit:
        return "You have used this month's $_limit free transcripts";
    }
  }

  String get _body {
    switch (reason) {
      case UpsellReason.notebookLimit:
        return 'Your notebooks and cards are safe. To add more notebooks, '
            'get Plus.';
      case UpsellReason.scanLimit:
        return 'Everything you already scanned is safe. To scan more papers '
            'now, and every month after, get Plus.';
      case UpsellReason.transcriptLimit:
        return 'The audio is safe in your card. To turn it into text now, '
            'and every time after, get Plus.';
    }
  }

  String get _perk {
    switch (reason) {
      case UpsellReason.notebookLimit:
        return 'Unlimited notebooks, plus scans without a monthly count.';
      case UpsellReason.scanLimit:
        return 'Unlimited scans, searchable scan text and renewal reminders.';
      case UpsellReason.transcriptLimit:
        return 'Voice to text without a monthly count.';
    }
  }

  String get _dismiss {
    switch (reason) {
      case UpsellReason.transcriptLimit:
        return 'Keep the audio only';
      case UpsellReason.notebookLimit:
      case UpsellReason.scanLimit:
        return 'Not now';
    }
  }

  bool get _monthly => reason != UpsellReason.notebookLimit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final VarnaColors c = VarnaColors.of(context);
    final AppSettings? settings = ref.watch(settingsProvider).valueOrNull;
    final int notebooks = ref.watch(notebooksProvider).valueOrNull?.length ?? 0;
    final int used;
    switch (reason) {
      case UpsellReason.notebookLimit:
        used = notebooks;
      case UpsellReason.scanLimit:
        used = settings?.usage.scans ?? _limit;
      case UpsellReason.transcriptLimit:
        used = settings?.usage.transcripts ?? _limit;
    }
    final double fill = _limit == 0 ? 1 : (used / _limit).clamp(0.0, 1.0);
    final int perMonth = (AppConfig.plusPriceInr / 12).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 10),
        Text(
          _kicker,
          style: bodyStyle(context, 14, weight: FontWeight.w700, color: c.muted),
        ),
        const SizedBox(height: 6),
        Text(_title, style: displayStyle(context, 28, letterSpacing: -0.6)),
        const SizedBox(height: 10),
        Text(_body, style: bodyStyle(context, 16, color: c.muted, height: 1.45)),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 8,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      ColoredBox(color: c.hairline),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: fill,
                        child: ColoredBox(color: c.ink),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '$used of $_limit',
              style: bodyStyle(context, 14, weight: FontWeight.w700),
            ),
          ],
        ),
        if (_monthly)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Resets on ${nextMonthStart(ref.watch(clockProvider)())}',
              style: bodyStyle(context, 13, color: c.muted),
            ),
          ),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: c.cardColor(0),
            borderRadius: BorderRadius.circular(VarnaMetrics.cardRadius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${AppConfig.appName} Plus, ${AppConfig.plusPrice}',
                style: displayStyle(context, 20, letterSpacing: -0.2),
              ),
              const SizedBox(height: 4),
              Text(
                '$_perk About ₹$perMonth a month.',
                style: bodyStyle(context, 15, height: 1.45),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        VarnaButton(
          label: 'Try Plus free for ${AppConfig.trialDays} days',
          onPressed: () => Navigator.of(context).pop(true),
        ),
        const SizedBox(height: 4),
        VarnaButton(
          label: _dismiss,
          kind: VarnaButtonKind.text,
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ],
    );
  }
}
