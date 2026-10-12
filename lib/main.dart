import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sembast/sembast.dart';

import 'app/app.dart';
import 'app_config.dart';
import 'core/providers.dart';
import 'core/theme/varna_colors.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _Bootstrap());
}

/// Opens the database, then starts the real app. Shows a small splash while
/// that happens (and a message if it fails).
class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late final Future<Database> _database = openAppDatabase();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Database>(
      future: _database,
      builder: (BuildContext context, AsyncSnapshot<Database> snapshot) {
        final Database? db = snapshot.data;
        if (db != null) {
          return ProviderScope(
            overrides: <Override>[databaseProvider.overrideWithValue(db)],
            child: const VarnaApp(),
          );
        }
        return MaterialApp(
          title: AppConfig.appName,
          debugShowCheckedModeBanner: false,
          theme: buildVarnaTheme(),
          home: _Splash(failed: snapshot.hasError),
        );
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash({required this.failed});

  final bool failed;

  @override
  Widget build(BuildContext context) {
    final VarnaColors c = VarnaColors.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                AppConfig.appName.toLowerCase(),
                style: text.headlineMedium,
              ),
              const SizedBox(height: 16),
              if (failed)
                Text(
                  'Could not open your notes on this device.',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(color: c.danger),
                )
              else
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
