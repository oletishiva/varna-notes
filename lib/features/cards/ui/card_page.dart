import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import 'checklist_card_screen.dart';
import 'photo_card_screen.dart';
import 'text_card_screen.dart';
import 'voice_card_screen.dart';
import 'widgets/card_unavailable.dart';

/// Route `/card/:id`: loads the card and shows the editor for its type.
class CardPage extends ConsumerWidget {
  const CardPage({super.key, required this.cardId});

  final String cardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<NoteCard?> card = ref.watch(cardProvider(cardId));
    return card.when(
      loading: () => const CardLoading(),
      error: (Object error, StackTrace stack) =>
          const CardUnavailable(error: true),
      data: (NoteCard? value) {
        if (value == null) {
          return const CardUnavailable();
        }
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
