import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../shared/app_state.dart';
import '../../../shared/auth_gate.dart';
import 'checklist_card_screen.dart';
import 'photo_card_screen.dart';
import 'text_card_screen.dart';
import 'voice_card_screen.dart';
import 'widgets/card_unavailable.dart';

/// Route `/card/:id`: loads the card and shows the editor for its type.
///
/// A card in a locked notebook is only shown once that notebook is unlocked
/// (the same authentication as opening the notebook); until then the page
/// shows a neutral lock screen.
class CardPage extends ConsumerStatefulWidget {
  const CardPage({super.key, required this.cardId});

  final String cardId;

  @override
  ConsumerState<CardPage> createState() => _CardPageState();
}

class _CardPageState extends ConsumerState<CardPage> {
  bool _prompting = false;
  String? _autoPromptedFor;

  Future<void> _unlock(String notebookId) async {
    if (_prompting) {
      return;
    }
    _prompting = true;
    final bool ok = await authenticateUser(reason: 'Unlock this note');
    _prompting = false;
    if (!mounted || !ok) {
      return;
    }
    ref.read(unlockedNotebooksProvider.notifier).update(
          (Set<String> s) => <String>{...s, notebookId},
        );
  }

  /// Asks once per notebook as soon as the lock screen appears.
  void _promptOnce(String notebookId) {
    if (_autoPromptedFor == notebookId) {
      return;
    }
    _autoPromptedFor = notebookId;
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (mounted) {
        unawaited(_unlock(notebookId));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<NoteCard?> card = ref.watch(cardProvider(widget.cardId));
    return card.when(
      loading: () => const CardLoading(),
      error: (Object error, StackTrace stack) =>
          const CardUnavailable(error: true),
      data: (NoteCard? value) {
        if (value == null) {
          return const CardUnavailable();
        }
        final AsyncValue<Notebook?> notebook =
            ref.watch(notebookProvider(value.notebookId));
        final Set<String> unlocked = ref.watch(unlockedNotebooksProvider);
        if (notebook.hasError && !notebook.hasValue) {
          return const CardUnavailable(error: true);
        }
        if (!notebook.hasValue) {
          // Do not show the card before we know whether it is locked.
          return const CardLoading();
        }
        final Notebook? nb = notebook.value;
        if (nb != null && nb.locked && !unlocked.contains(nb.id)) {
          _promptOnce(nb.id);
          return CardLocked(onUnlock: () => unawaited(_unlock(nb.id)));
        }
        // Unlocked again later (or after being locked): ask again next time.
        _autoPromptedFor = null;
        switch (value.type) {
          case CardType.text:
          case CardType.link:
            return TextCardScreen(key: ValueKey<String>(value.id), cardId: value.id);
          case CardType.checklist:
            return ChecklistCardScreen(
              key: ValueKey<String>(value.id),
              cardId: value.id,
            );
          case CardType.voice:
            return VoiceCardScreen(key: ValueKey<String>(value.id), cardId: value.id);
          case CardType.photo:
          case CardType.scan:
            return PhotoCardScreen(key: ValueKey<String>(value.id), cardId: value.id);
        }
      },
    );
  }
}
