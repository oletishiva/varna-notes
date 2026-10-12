import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app_config.dart';
import '../../../core/data/attachment_store.dart';
import '../../../core/data/notes_repository.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/services/ai_service.dart';
import '../../../core/services/reminder_service.dart';
import '../../../core/services/usage_limits.dart';
import '../../../core/theme/varna_colors.dart';
import 'widgets/card_actions.dart';
import 'widgets/card_saver.dart';
import 'widgets/card_title_field.dart';
import 'widgets/card_unavailable.dart';
import 'widgets/color_dots.dart';
import 'widgets/format_utils.dart';
import 'widgets/tinted_card_scaffold.dart';
import 'widgets/ui_kit.dart';

/// Player/editor for voice cards: play/pause, seek bar, editable title and a
/// transcript section.
///
/// There is no speech service in this build: without a configured
/// [AiService] the transcript section says so and nothing is invented.
class VoiceCardScreen extends ConsumerWidget {
  const VoiceCardScreen({super.key, required this.cardId});

  final String cardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<NoteCard?> card = ref.watch(cardProvider(cardId));
    return card.when(
      loading: () => const CardLoading(),
      error: (Object e, StackTrace s) => const CardUnavailable(error: true),
      data: (NoteCard? value) {
        if (value == null) {
          return const CardUnavailable();
        }
        return _VoiceEditor(card: value);
      },
    );
  }
}

class _VoiceEditor extends ConsumerStatefulWidget {
  const _VoiceEditor({required this.card});

  final NoteCard card;

  @override
  ConsumerState<_VoiceEditor> createState() => _VoiceEditorState();
}

class _VoiceEditorState extends ConsumerState<_VoiceEditor> {
  late final NotesRepository _repo;
  late final AttachmentStore _attachments;
  late final ReminderService _reminders;
  late final AiService _ai;
  late final UsageLimits _limits;
  late final CardSaver _saver;
  late final Autosaver _autosaver;
  late final TextEditingController _title;
  final FocusNode _titleFocus = FocusNode();

  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subs =
      <StreamSubscription<dynamic>>[];

  BytesSource? _source;
  String? _loadError;
  PlayerState _state = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double? _dragMs;
  bool _deleted = false;
  bool _transcribing = false;
  String _language = 'en';

  Attachment? get _audio {
    for (final Attachment a in widget.card.attachments) {
      if (a.kind == AttachmentKind.audio) {
        return a;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _repo = ref.read(notesRepositoryProvider);
    _attachments = ref.read(attachmentStoreProvider);
    _reminders = ref.read(reminderServiceProvider);
    _ai = ref.read(aiServiceProvider);
    _limits = ref.read(usageLimitsProvider);
    _saver = CardSaver(_repo, widget.card.id);
    _title = TextEditingController(text: widget.card.title);
    _autosaver = Autosaver(onSave: _saveTitle);
    final int? ms = _audio?.durationMs;
    if (ms != null) {
      _duration = Duration(milliseconds: ms);
    }
    _listenToPlayer();
    if (_audio == null) {
      _loadError = 'This card has no recording.';
    } else {
      unawaited(_loadAudio());
    }
  }

  void _listenToPlayer() {
    _subs.add(_player.onPlayerStateChanged.listen((PlayerState s) {
      if (mounted) {
        setState(() => _state = s);
      }
    }));
    _subs.add(_player.onPositionChanged.listen((Duration p) {
      if (mounted && _dragMs == null) {
        setState(() => _position = p);
      }
    }));
    _subs.add(_player.onDurationChanged.listen((Duration d) {
      if (mounted && d > Duration.zero) {
        setState(() => _duration = d);
      }
    }));
    _subs.add(_player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _position = Duration.zero;
          _state = PlayerState.stopped;
        });
      }
    }));
  }

  Future<void> _loadAudio() async {
    final Attachment? audio = _audio;
    if (audio == null) {
      return;
    }
    try {
      final Uint8List? bytes = await _attachments.read(audio.id);
      if (!mounted) {
        return;
      }
      if (bytes == null || bytes.isEmpty) {
        setState(() {
          _loadError = 'The recording is not on this device yet. '
              'Sync again to download it.';
        });
        return;
      }
      setState(() {
        _source = BytesSource(bytes, mimeType: audioMimeType(audio.fileName));
      });
    } catch (_) {
      if (mounted) {
        setState(() => _loadError = 'The recording could not be loaded.');
      }
    }
  }

  Future<void> _saveTitle() async {
    final String title = _title.text;
    await _saver.update((NoteCard c) {
      return c.title == title ? c : c.copyWith(title: title);
    });
  }

  @override
  void didUpdateWidget(_VoiceEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool editing = _autosaver.hasPendingChanges ||
        _autosaver.isSaving ||
        _titleFocus.hasFocus;
    if (!editing && _title.text != widget.card.title) {
      _title.text = widget.card.title;
    }
  }

  @override
  void dispose() {
    if (!_deleted) {
      _autosaver.dispose();
    }
    for (final StreamSubscription<dynamic> sub in _subs) {
      unawaited(sub.cancel());
    }
    unawaited(_player.dispose());
    _title.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  Future<void> _goBack() async {
    await _autosaver.flush();
    if (!mounted) {
      return;
    }
    leaveScreen(context);
  }

  Future<void> _deleteCard() async {
    final bool ok = await confirmDelete(
      context,
      title: 'Delete this voice note?',
    );
    if (!ok || !mounted) {
      return;
    }
    _deleted = true;
    final String id = widget.card.id;
    leaveScreen(context);
    await _reminders.cancel(id);
    await _repo.deleteCard(id);
  }

  Future<void> _togglePlay() async {
    final BytesSource? source = _source;
    if (source == null) {
      return;
    }
    try {
      if (_state == PlayerState.playing) {
        await _player.pause();
      } else if (_state == PlayerState.paused) {
        await _player.resume();
      } else {
        await _player.play(source);
      }
    } catch (_) {
      if (mounted) {
        showInfo(context, 'This recording could not be played.');
      }
    }
  }

  Future<void> _seekTo(double ms) async {
    final Duration target = Duration(milliseconds: ms.round());
    setState(() {
      _dragMs = null;
      _position = target;
    });
    try {
      if (_state == PlayerState.stopped || _state == PlayerState.completed) {
        final BytesSource? source = _source;
        if (source == null) {
          return;
        }
        await _player.play(source, position: target);
      } else {
        await _player.seek(target);
      }
    } catch (_) {
      // Seeking is best effort.
    }
  }

  Future<void> _transcribe() async {
    final Attachment? audio = _audio;
    if (audio == null || _transcribing) {
      return;
    }
    setState(() => _transcribing = true);
    try {
      final LimitCheck check = await _limits.canTranscribe();
      if (!mounted) {
        return;
      }
      if (!check.allowed) {
        await _showLimitDialog(check.message);
        return;
      }
      final Uint8List? bytes = await _attachments.read(audio.id);
      if (!mounted) {
        return;
      }
      if (bytes == null) {
        showInfo(context, 'The recording is not on this device yet.');
        return;
      }
      final String text =
          (await _ai.transcribe(bytes, languageCode: _language)).trim();
      await _limits.recordTranscript();
      await _saver.update((NoteCard c) => c.copyWith(transcript: text));
    } catch (_) {
      if (mounted) {
        showInfo(context, 'The transcript could not be made right now.');
      }
    } finally {
      if (mounted) {
        setState(() => _transcribing = false);
      }
    }
  }

  Future<void> _showLimitDialog(String message) async {
    final bool? upgrade = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Transcript limit reached'),
          content: Text(message),
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

  @override
  Widget build(BuildContext context) {
    final VarnaColors colors = VarnaColors.of(context);
    final NoteCard card = widget.card;
    final AsyncValue<Notebook?> notebook =
        ref.watch(notebookProvider(card.notebookId));
    final AsyncValue<AppSettings> settings = ref.watch(settingsProvider);
    final SyncProviderId? provider = settings.value?.syncProvider;

    final Duration total = _duration;
    final double maxMs = math.max(1, total.inMilliseconds).toDouble();
    final double valueMs = math.min(
      _dragMs ?? _position.inMilliseconds.toDouble(),
      maxMs,
    );
    final bool playing = _state == PlayerState.playing;
    final bool ready = _source != null;

    final String notebookName = notebook.value?.title ?? '';
    final String meta = <String>[
      if (notebookName.isNotEmpty) notebookName,
      if (total > Duration.zero) formatClock(total),
      'edited ${editedLabel(card.updatedAt, DateTime.now())}',
    ].join(', ');

    final Widget player = Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 16, 12),
      decoration: BoxDecoration(
        color: frostedWhite(),
        borderRadius: BorderRadius.circular(20),
      ),
      child: _loadError != null
          ? Row(
              children: <Widget>[
                Icon(Icons.error_outline, color: colors.danger),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _loadError!,
                    style: bodyStyle(context, 15, height: 1.4),
                  ),
                ),
              ],
            )
          : Row(
              children: <Widget>[
                IconButton(
                  tooltip: playing ? 'Pause' : 'Play recording',
                  onPressed: ready ? () => unawaited(_togglePlay()) : null,
                  icon: Icon(
                    playing ? Icons.pause : Icons.play_arrow,
                    size: 32,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: colors.ink,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: colors.ink.withValues(alpha: 0.3),
                    disabledForegroundColor: Colors.white,
                    fixedSize: const Size(60, 60),
                    minimumSize: const Size(60, 60),
                    shape: const CircleBorder(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: colors.ink,
                          inactiveTrackColor: colors.ink.withValues(alpha: 0.2),
                          thumbColor: colors.ink,
                          overlayColor: colors.ink.withValues(alpha: 0.12),
                        ),
                        child: Slider(
                          min: 0,
                          max: maxMs,
                          value: valueMs,
                          semanticFormatterCallback: (double v) => formatClock(
                            Duration(milliseconds: v.round()),
                          ),
                          onChanged: ready
                              ? (double v) => setState(() => _dragMs = v)
                              : null,
                          onChangeEnd: (double v) => unawaited(_seekTo(v)),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Text(
                              formatClock(
                                Duration(milliseconds: valueMs.round()),
                              ),
                              style: bodyStyle(context, 13,
                                  weight: FontWeight.w600),
                            ),
                            Text(
                              formatClock(total),
                              style: bodyStyle(context, 13,
                                  weight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );

    final Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 22),
        CardTitleField(
          controller: _title,
          focusNode: _titleFocus,
          hintText: 'Name this voice note',
          onChanged: (_) => _autosaver.markChanged(),
        ),
        const SizedBox(height: 6),
        Text(meta, style: bodyStyle(context, 13, weight: FontWeight.w600)),
        const SizedBox(height: 20),
        player,
        const SizedBox(height: 16),
        _TranscriptSection(
          transcript: (card.transcript ?? '').trim(),
          aiConfigured: _ai.isConfigured,
          busy: _transcribing,
          language: _language,
          onLanguage: (String code) => setState(() => _language = code),
          onTranscribe: () => unawaited(_transcribe()),
        ),
        const SizedBox(height: 24),
      ],
    );

    final Widget footer = Align(
      alignment: Alignment.centerLeft,
      child: CardColorDots(
        selected: card.colorIndex,
        onSelected: (int index) {
          unawaited(_saver.update(
            (NoteCard c) => c.copyWith(colorIndex: index),
          ));
        },
      ),
    );

    return TintedCardScaffold(
      tint: colors.cardColor(card.colorIndex),
      onBack: () => unawaited(_goBack()),
      status: _autosaver.status,
      destinationLabel: provider?.displayName,
      favourite: card.favourite,
      onToggleFavourite: () {
        unawaited(_saver.update(
          (NoteCard c) => c.copyWith(favourite: !c.favourite),
        ));
      },
      onDelete: () => unawaited(_deleteCard()),
      content: content,
      footer: footer,
    );
  }
}

class _TranscriptSection extends StatelessWidget {
  const _TranscriptSection({
    required this.transcript,
    required this.aiConfigured,
    required this.busy,
    required this.language,
    required this.onLanguage,
    required this.onTranscribe,
  });

  final String transcript;
  final bool aiConfigured;
  final bool busy;
  final String language;
  final ValueChanged<String> onLanguage;
  final VoidCallback onTranscribe;

  @override
  Widget build(BuildContext context) {
    final VarnaColors colors = VarnaColors.of(context);
    final Widget body;
    if (transcript.isNotEmpty) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Transcript', style: bodyStyle(context, 13, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          SelectableText(
            transcript,
            style: bodyStyle(context, 16, height: 1.5),
          ),
        ],
      );
    } else if (!aiConfigured) {
      body = Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(
              text: 'Transcript:',
              style: bodyStyle(context, 14, weight: FontWeight.w700),
            ),
            TextSpan(
              text: ' available in ${AppConfig.appName} Plus '
                  '(not available in this build)',
              style: bodyStyle(context, 14, color: colors.muted),
            ),
          ],
        ),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Transcript', style: bodyStyle(context, 13, weight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilterPill(
                label: 'English',
                selected: language == 'en',
                onTap: () => onLanguage('en'),
              ),
              FilterPill(
                label: 'Telugu',
                selected: language == 'te',
                onTap: () => onLanguage('te'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (busy)
            Row(
              children: <Widget>[
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Making the transcript...',
                    style: bodyStyle(context, 15, color: colors.muted),
                  ),
                ),
              ],
            )
          else
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(88, 48)),
              onPressed: onTranscribe,
              child: const Text('Transcribe'),
            ),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: frostedWhite(),
        borderRadius: BorderRadius.circular(16),
      ),
      child: body,
    );
  }
}
