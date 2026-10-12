import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/data/notes_repository.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/services/ai_service.dart';
import '../../../core/theme/varna_colors.dart';
import '../../cards/ui/widgets/format_utils.dart';
import '../../cards/ui/widgets/markdown_format.dart';
import '../../cards/ui/widgets/tinted_card_scaffold.dart';
import '../../cards/ui/widgets/ui_kit.dart';

class _Source {
  const _Source({
    required this.cardId,
    required this.title,
    required this.type,
    required this.colorIndex,
  });

  final String cardId;
  final String title;
  final CardType type;
  final int colorIndex;
}

class _Message {
  const _Message({
    required this.text,
    required this.isUser,
    this.sources = const <_Source>[],
    this.failed = false,
  });

  final String text;
  final bool isUser;
  final List<_Source> sources;
  final bool failed;
}

class _Scored {
  _Scored(this.hit) : score = 1;

  final SearchHit hit;
  int score;
}

const Set<String> _stopWords = <String>{
  'the', 'and', 'for', 'are', 'was', 'were', 'what', 'when', 'where', 'which',
  'who', 'whom', 'how', 'why', 'did', 'does', 'has', 'have', 'had', 'with',
  'about', 'from', 'that', 'this', 'these', 'those', 'there', 'then', 'than',
  'you', 'your', 'mine', 'our', 'his', 'her', 'its', 'any', 'all', 'can',
  'could', 'would', 'should', 'will', 'shall', 'may', 'might', 'tell', 'say',
  'said', 'into', 'out', 'not', 'but', 'just', 'some', 'much', 'many',
};

/// "Ask your notes": a chat that answers from the user's own cards.
///
/// When [AiService.isConfigured] is false (the default in v1) it shows a calm
/// "coming soon" state and a disabled input. Nothing is faked.
class AskScreen extends ConsumerStatefulWidget {
  const AskScreen({super.key});

  @override
  ConsumerState<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends ConsumerState<AskScreen> {
  late final NotesRepository _repo;
  late final AiService _ai;
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<_Message> _messages = <_Message>[];
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(notesRepositoryProvider);
    _ai = ref.read(aiServiceProvider);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<String> _keywords(String question) {
    final RegExp word = RegExp(r'[\p{L}\p{M}\p{N}]+', unicode: true);
    final List<String> found = <String>[];
    for (final RegExpMatch m in word.allMatches(question.toLowerCase())) {
      final String w = m.group(0) ?? '';
      if (w.length >= 3 && !_stopWords.contains(w) && !found.contains(w)) {
        found.add(w);
      }
    }
    return found.length > 6 ? found.sublist(0, 6) : found;
  }

  /// The cards that mention the most words of the question (top five).
  Future<List<SearchHit>> _retrieve(String question) async {
    final Map<String, _Scored> scored = <String, _Scored>{};
    for (final String word in _keywords(question)) {
      final List<SearchHit> hits = await _repo.search(word, limit: 20);
      for (final SearchHit hit in hits) {
        final _Scored? existing = scored[hit.card.id];
        if (existing == null) {
          scored[hit.card.id] = _Scored(hit);
        } else {
          existing.score++;
        }
      }
    }
    final List<_Scored> ordered = scored.values.toList()
      ..sort((_Scored a, _Scored b) {
        final int c = b.score.compareTo(a.score);
        return c != 0
            ? c
            : b.hit.card.updatedAt.compareTo(a.hit.card.updatedAt);
      });
    return ordered.take(5).map((_Scored s) => s.hit).toList();
  }

  String _contextFor(NoteCard card) {
    final List<String> parts = <String>[
      'Title: ${displayTitle(card)}',
      'Type: ${cardTypeLabel(card.type)}',
    ];
    if (card.body.trim().isNotEmpty) {
      parts.add(card.body.trim());
    }
    if (card.items.isNotEmpty) {
      parts.add(card.items
          .map((ChecklistItem i) => '${i.done ? '[x]' : '[ ]'} ${i.text}')
          .join('\n'));
    }
    if ((card.ocrText ?? '').trim().isNotEmpty) {
      parts.add('Scanned text: ${card.ocrText!.trim()}');
    }
    if ((card.transcript ?? '').trim().isNotEmpty) {
      parts.add('Voice transcript: ${card.transcript!.trim()}');
    }
    final DateTime? expiry = card.expiryDate;
    if (expiry != null) {
      parts.add('Expiry date: ${DateFormat('d MMMM yyyy').format(expiry)}');
    }
    final String text = parts.join('\n');
    return text.length > 1800 ? text.substring(0, 1800) : text;
  }

  void _add(_Message message) {
    setState(() => _messages.add(message));
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (_scroll.hasClients) {
        unawaited(_scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        ));
      }
    });
  }

  Future<void> _send() async {
    final String question = _controller.text.trim();
    if (question.isEmpty || _sending || !_ai.isConfigured) {
      return;
    }
    _controller.clear();
    _add(_Message(text: question, isUser: true));
    setState(() => _sending = true);
    try {
      final List<SearchHit> hits = await _retrieve(question);
      if (!mounted) {
        return;
      }
      if (hits.isEmpty) {
        _add(const _Message(
          text: 'I could not find anything about that in your cards. Try '
              'other words, or add the details to a card first.',
          isUser: false,
        ));
        return;
      }
      final String answer = await _ai.ask(
        question,
        context: hits.map((SearchHit h) => _contextFor(h.card)).toList(),
      );
      if (!mounted) {
        return;
      }
      _add(_Message(
        text: answer.trim(),
        isUser: false,
        sources: <_Source>[
          for (final SearchHit h in hits)
            _Source(
              cardId: h.card.id,
              title: displayTitle(h.card),
              type: h.card.type,
              colorIndex: h.card.colorIndex,
            ),
        ],
      ));
    } catch (_) {
      if (mounted) {
        _add(const _Message(
          text: 'Sorry, I could not get an answer right now. Please try '
              'again in a moment.',
          isUser: false,
          failed: true,
        ));
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final VarnaColors colors = VarnaColors.of(context);
    final bool ready = _ai.isConfigured;

    final Widget content;
    if (!ready) {
      content = const _ComingSoon();
    } else if (_messages.isEmpty && !_sending) {
      content = const _AskHint();
    } else {
      content = ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.only(top: 16, bottom: 12),
        itemCount: _messages.length + (_sending ? 1 : 0),
        itemBuilder: (BuildContext context, int index) {
          if (index >= _messages.length) {
            return const _Thinking();
          }
          return _Bubble(
            message: _messages[index],
            onOpenSource: (String id) => unawaited(context.push('/card/$id')),
          );
        },
      );
    }

    return Scaffold(
      backgroundColor: colors.ground,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      RoundIconButton(
                        icon: Icons.arrow_back,
                        tooltip: 'Back',
                        background: colors.surface,
                        onPressed: () => leaveScreen(context),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Ask your notes',
                          style: displayStyle(context, 26),
                        ),
                      ),
                    ],
                  ),
                  Expanded(child: content),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      ready
                          ? 'Answers come only from your own cards, with the '
                              'source shown.'
                          : 'Answers will come only from your own cards, with '
                              'the source shown.',
                      textAlign: TextAlign.center,
                      style: bodyStyle(
                        context,
                        13,
                        color: colors.muted,
                        height: 1.4,
                      ),
                    ),
                  ),
                  _InputBar(
                    controller: _controller,
                    enabled: ready,
                    sending: _sending,
                    onSend: () => unawaited(_send()),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ComingSoon extends StatelessWidget {
  const _ComingSoon();

  @override
  Widget build(BuildContext context) {
    final VarnaColors colors = VarnaColors.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: colors.cardColor(0),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.auto_awesome, size: 32, color: colors.ink),
            ),
            const SizedBox(height: 18),
            Text(
              'Ask your notes is coming soon',
              textAlign: TextAlign.center,
              style: displayStyle(context, 24),
            ),
            const SizedBox(height: 10),
            Text(
              'Soon you will be able to ask things like "When does my car '
              'insurance expire?" and get an answer taken only from your own '
              'cards, with the source shown. It needs an online service that '
              'is not part of this version, so for now Search is the fastest '
              'way to find things, and it works offline.',
              textAlign: TextAlign.center,
              style: bodyStyle(context, 15, color: colors.muted, height: 1.5),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => unawaited(context.push('/search')),
              icon: const Icon(Icons.search),
              label: const Text('Search your cards'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AskHint extends StatelessWidget {
  const _AskHint();

  @override
  Widget build(BuildContext context) {
    final VarnaColors colors = VarnaColors.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.chat_bubble_outline, size: 40, color: colors.muted),
            const SizedBox(height: 12),
            Text(
              'Ask about anything in your cards',
              textAlign: TextAlign.center,
              style: displayStyle(context, 22),
            ),
            const SizedBox(height: 8),
            Text(
              'For example: "When does my car insurance expire?" or "What did '
              'the hotel say about check-in?"',
              textAlign: TextAlign.center,
              style: bodyStyle(context, 15, color: colors.muted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) {
    final VarnaColors colors = VarnaColors.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomRight: Radius.circular(20),
            bottomLeft: Radius.circular(6),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                'Looking through your cards...',
                style: bodyStyle(context, 15, color: colors.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.onOpenSource});

  final _Message message;
  final ValueChanged<String> onOpenSource;

  @override
  Widget build(BuildContext context) {
    final VarnaColors colors = VarnaColors.of(context);
    if (message.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 280),
          margin: const EdgeInsets.only(top: 14),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: colors.ink,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(6),
            ),
          ),
          child: SelectableText(
            message.text,
            style: bodyStyle(context, 16, color: Colors.white, height: 1.4),
          ),
        ),
      );
    }
    final TextStyle textStyle = bodyStyle(
      context,
      16,
      color: message.failed ? colors.danger : colors.ink,
      height: 1.5,
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomRight: Radius.circular(20),
            bottomLeft: Radius.circular(6),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SelectableText.rich(
              TextSpan(
                style: textStyle,
                children: markdownSpans(message.text, textStyle),
              ),
            ),
            if (message.sources.isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              Text(
                'From your cards',
                style: bodyStyle(
                  context,
                  13,
                  weight: FontWeight.w700,
                  color: colors.muted,
                ),
              ),
              const SizedBox(height: 8),
              for (final _Source source in message.sources)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: colors.cardColor(source.colorIndex),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => onOpenSource(source.cardId),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 52),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      source.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: bodyStyle(
                                        context,
                                        15,
                                        weight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      cardTypeLabel(source.type),
                                      style: bodyStyle(
                                        context,
                                        12,
                                        weight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_forward, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.enabled,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final VarnaColors colors = VarnaColors.of(context);
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.fromLTRB(18, 0, 6, 0),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                textCapitalization: TextCapitalization.sentences,
                style: bodyStyle(context, 16),
                decoration: InputDecoration(
                  hintText: 'Ask in English or Telugu',
                  hintStyle: bodyStyle(context, 16, color: colors.muted),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            RoundIconButton(
              icon: Icons.arrow_upward,
              tooltip: 'Send question',
              background: colors.cardColor(0),
              onPressed: (enabled && !sending) ? onSend : null,
            ),
          ],
        ),
      ),
    );
  }
}
