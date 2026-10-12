import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The notebook the user opened last; the centre "+" button adds cards there.
final lastNotebookIdProvider = StateProvider<String?>((ref) => null);

/// Locked notebooks the user has already unlocked in this app session.
final unlockedNotebooksProvider =
    StateProvider<Set<String>>((ref) => <String>{});
