import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers.dart';
import '../features/ask/ui/ask_screen.dart';
import '../features/cards/ui/card_page.dart';
import '../features/cards/ui/new_card_sheet.dart';
import '../features/cards/ui/voice_recorder_screen.dart';
import '../features/notebooks/ui/notebook_screen.dart';
import '../features/notebooks/ui/notebooks_screen.dart';
import '../features/onboarding/ui/sync_setup_screen.dart';
import '../features/onboarding/ui/welcome_screen.dart';
import '../features/papers/ui/papers_screen.dart';
import '../features/plus/ui/paywall_screen.dart';
import '../features/reminders/ui/reminders_screen.dart';
import '../features/scan/ui/scan_screen.dart';
import '../features/search/ui/search_screen.dart';
import '../features/settings/ui/conflict_screen.dart';
import '../features/settings/ui/settings_screen.dart';
import '../features/settings/ui/sync_settings_screen.dart';
import 'shell.dart';

/// Paths shown before onboarding is finished.
const Set<String> _onboardingPaths = <String>{'/welcome', '/sync-setup'};

/// The app's router. Until onboarding is done everything redirects to
/// `/welcome`.
final routerProvider = Provider<GoRouter>((ref) {
  final GoRouter router = GoRouter(
    initialLocation: '/',
    redirect: (BuildContext context, GoRouterState state) async {
      final bool done =
          await ref.read(settingsRepositoryProvider).getOnboardingDone();
      final String path = state.uri.path;
      if (!done && !_onboardingPaths.contains(path)) {
        return '/welcome';
      }
      if (done && path == '/welcome') {
        return '/';
      }
      return null;
    },
    errorBuilder: (BuildContext context, GoRouterState state) => Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text('This page does not exist.'),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.go('/'),
                child: const Text('Back to notebooks'),
              ),
            ],
          ),
        ),
      ),
    ),
    routes: <RouteBase>[
      // Tabs, inside the shell with the bottom bar.
      ShellRoute(
        builder: (BuildContext context, GoRouterState state, Widget child) =>
            AppShell(location: state.uri.path, child: child),
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            pageBuilder: (BuildContext context, GoRouterState state) =>
                NoTransitionPage<void>(
              key: state.pageKey,
              child: const NotebooksScreen(),
            ),
          ),
          GoRoute(
            path: '/papers',
            pageBuilder: (BuildContext context, GoRouterState state) =>
                NoTransitionPage<void>(
              key: state.pageKey,
              child: const PapersScreen(),
            ),
          ),
          GoRoute(
            path: '/reminders',
            pageBuilder: (BuildContext context, GoRouterState state) =>
                NoTransitionPage<void>(
              key: state.pageKey,
              child: const RemindersScreen(),
            ),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (BuildContext context, GoRouterState state) =>
                NoTransitionPage<void>(
              key: state.pageKey,
              child: const SettingsScreen(),
            ),
          ),
        ],
      ),

      // Onboarding.
      GoRoute(
        path: '/welcome',
        builder: (BuildContext context, GoRouterState state) =>
            const WelcomeScreen(),
      ),
      GoRoute(
        path: '/sync-setup',
        builder: (BuildContext context, GoRouterState state) =>
            const SyncSetupScreen(),
      ),

      // Notebooks and cards.
      GoRoute(
        path: '/notebook/:id',
        builder: (BuildContext context, GoRouterState state) =>
            NotebookScreen(notebookId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: '/card/:id',
        builder: (BuildContext context, GoRouterState state) =>
            CardPage(cardId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: '/new-card/:notebookId',
        builder: (BuildContext context, GoRouterState state) =>
            NewCardScreen(notebookId: state.pathParameters['notebookId'] ?? ''),
      ),
      GoRoute(
        path: '/record/:notebookId',
        builder: (BuildContext context, GoRouterState state) =>
            VoiceRecorderScreen(
          notebookId: state.pathParameters['notebookId'] ?? '',
        ),
      ),
      GoRoute(
        path: '/scan/:notebookId',
        builder: (BuildContext context, GoRouterState state) => ScanScreen(
          notebookId: state.pathParameters['notebookId'] ?? '',
        ),
      ),

      // Search, papers (also a tab), ask.
      GoRoute(
        path: '/search',
        builder: (BuildContext context, GoRouterState state) =>
            const SearchScreen(),
      ),
      GoRoute(
        path: '/ask',
        builder: (BuildContext context, GoRouterState state) =>
            const AskScreen(),
      ),

      // Settings sub pages and Plus.
      GoRoute(
        path: '/settings/sync',
        builder: (BuildContext context, GoRouterState state) =>
            const SyncSettingsScreen(),
      ),
      GoRoute(
        path: '/settings/sync/conflicts',
        builder: (BuildContext context, GoRouterState state) =>
            const ConflictsListScreen(),
      ),
      GoRoute(
        path: '/conflict/:id',
        builder: (BuildContext context, GoRouterState state) =>
            ConflictScreen(conflictId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: '/paywall',
        builder: (BuildContext context, GoRouterState state) =>
            const PaywallScreen(),
      ),
    ],
  );

  ref.onDispose(router.dispose);
  return router;
});
