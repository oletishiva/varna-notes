import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varna/core/theme/varna_theme.dart';
import 'package:varna/features/onboarding/ui/welcome_screen.dart';
import 'package:varna/features/sync/logic/sync_status.dart';
import 'package:varna/shared/widgets/status_chip.dart';

Widget _host(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      theme: VarnaTheme.light(),
      home: child,
    ),
  );
}

void main() {
  testWidgets('Welcome screen shows the headline and Get started', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(const WelcomeScreen()));
    await tester.pump();

    expect(find.text('Every thought gets its own card.'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
  });

  testWidgets('Status chip says Synced for a finished sync', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Scaffold(
          body: StatusChip(status: SyncSynced(DateTime.utc(2026, 10, 12))),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Synced'), findsOneWidget);
  });
}
