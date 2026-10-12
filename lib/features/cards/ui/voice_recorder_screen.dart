import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:path_provider/path_provider.dart' show getTemporaryDirectory;
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../../../app_config.dart';
import '../../../core/data/attachment_store.dart';
import '../../../core/data/notes_repository.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/theme/varna_colors.dart';
import 'widgets/card_actions.dart';
import 'widgets/format_utils.dart';
import 'widgets/tinted_card_scaffold.dart';
import 'widgets/ui_kit.dart';

enum _Phase { starting, recording, paused, saving, denied, failed }

/// Records a voice note into [notebookId].
///
/// Uses the `record` package (7.x): `hasPermission()`, `start(RecordConfig,
/// path:)`, `pause()/resume()`, `stop()` which returns a file path on
/// Android/iOS and a blob URL on web (read with `package:http`), and
/// `onAmplitudeChanged` for the level bars. No transcript is shown while
/// recording because there is no speech service in this build.
class VoiceRecorderScreen extends ConsumerStatefulWidget {
  const VoiceRecorderScreen({super.key, required this.notebookId});

  final String notebookId;

  @override
  ConsumerState<VoiceRecorderScreen> createState() =>
      _VoiceRecorderScreenState();
}

class _VoiceRecorderScreenState extends ConsumerState<VoiceRecorderScreen> {
  late final NotesRepository _repo;
  late final AttachmentStore _store;
  final AudioRecorder _recorder = AudioRecorder();
  final Stopwatch _watch = Stopwatch();
  final List<double> _levels = <double>[];

  _Phase _phase = _Phase.starting;
  String? _error;
  String _extension = 'm4a';
  Timer? _ticker;
  StreamSubscription<Amplitude>? _ampSub;
  bool _gotAmplitude = false;
  double _latest = 0.1;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(notesRepositoryProvider);
    _store = ref.read(attachmentStoreProvider);
    unawaited(_start());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(_ampSub?.cancel());
    unawaited(_shutdown());
    super.dispose();
  }

  Future<void> _shutdown() async {
    try {
      if (await _recorder.isRecording() || await _recorder.isPaused()) {
        await _recorder.cancel();
      }
    } catch (_) {
      // Nothing more to do.
    }
    try {
      await _recorder.dispose();
    } catch (_) {
      // Nothing more to do.
    }
  }

  // --------------------------------------------------------------- recording

  Future<AudioEncoder> _chooseEncoder() async {
    if (!kIsWeb) {
      return AudioEncoder.aacLc;
    }
    // Browsers differ: Safari does AAC, Chrome and Firefox do Opus.
    const List<AudioEncoder> order = <AudioEncoder>[
      AudioEncoder.aacLc,
      AudioEncoder.opus,
      AudioEncoder.wav,
    ];
    for (final AudioEncoder encoder in order) {
      try {
        if (await _recorder.isEncoderSupported(encoder)) {
          return encoder;
        }
      } catch (_) {
        // Try the next one.
      }
    }
    return AudioEncoder.wav;
  }

  String _extensionFor(AudioEncoder encoder) {
    switch (encoder) {
      case AudioEncoder.opus:
        return kIsWeb ? 'webm' : 'opus';
      case AudioEncoder.wav:
        return 'wav';
      default:
        return 'm4a';
    }
  }

  Future<String> _recordingPath(String extension) async {
    final String name =
        'varna_voice_${DateTime.now().millisecondsSinceEpoch}.$extension';
    if (kIsWeb) {
      return name;
    }
    final dir = await getTemporaryDirectory();
    return '${dir.path}/$name';
  }

  Future<void> _retry() async {
    setState(() {
      _phase = _Phase.starting;
      _error = null;
    });
    await _start();
  }

  Future<void> _start() async {
    try {
      final bool allowed = await _recorder.hasPermission();
      if (!mounted) {
        return;
      }
      if (!allowed) {
        setState(() => _phase = _Phase.denied);
        return;
      }
      final AudioEncoder encoder = await _chooseEncoder();
      _extension = _extensionFor(encoder);
      final String path = await _recordingPath(_extension);
      if (!mounted) {
        return;
      }
      await _recorder.start(
        RecordConfig(encoder: encoder, numChannels: 1, bitRate: 96000),
        path: path,
      );
      if (!mounted) {
        return;
      }
      _levels.clear();
      _gotAmplitude = false;
      _watch
        ..reset()
        ..start();
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(milliseconds: 120), _onTick);
      unawaited(_ampSub?.cancel());
      _ampSub = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 110))
          .listen(
        (Amplitude a) {
          _gotAmplitude = true;
          // dBFS: about -50 (quiet) to 0 (loud).
          final double scaled = (a.current + 50) / 50;
          _latest = scaled < 0 ? 0 : (scaled > 1 ? 1 : scaled);
        },
        onError: (Object _) {},
      );
      setState(() => _phase = _Phase.recording);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _phase = _Phase.failed;
        _error = kIsWeb
            ? 'Recording did not start in this browser. Voice notes work best '
                'in the ${AppConfig.appName} mobile app.'
            : 'Recording could not be started. Please try again.';
      });
    }
  }

  void _onTick(Timer timer) {
    if (!mounted || _phase != _Phase.recording) {
      return;
    }
    final double level = _gotAmplitude
        ? _latest
        : 0.18 + 0.12 * (math.sin(_watch.elapsedMilliseconds / 260) + 1) / 2;
    _levels.add(level);
    if (_levels.length > 64) {
      _levels.removeAt(0);
    }
    setState(() {});
  }

  Future<void> _togglePause() async {
    try {
      if (_phase == _Phase.recording) {
        await _recorder.pause();
        _watch.stop();
        if (mounted) {
          setState(() => _phase = _Phase.paused);
        }
      } else if (_phase == _Phase.paused) {
        await _recorder.resume();
        _watch.start();
        if (mounted) {
          setState(() => _phase = _Phase.recording);
        }
      }
    } catch (_) {
      if (mounted) {
        showInfo(context, 'Could not pause or resume the recording.');
      }
    }
  }

  Future<void> _stopAndSave() async {
    if (_phase != _Phase.recording && _phase != _Phase.paused) {
      return;
    }
    final Duration elapsed = _watch.elapsed;
    _watch.stop();
    _ticker?.cancel();
    unawaited(_ampSub?.cancel());
    setState(() => _phase = _Phase.saving);
    try {
      final String? output = await _recorder.stop();
      if (output == null || output.isEmpty) {
        throw StateError('The recorder returned no file.');
      }
      final Uint8List bytes = kIsWeb
          ? await http.readBytes(Uri.parse(output))
          : await XFile(output).readAsBytes();
      if (bytes.isEmpty) {
        throw StateError('The recording is empty.');
      }
      final String attachmentId = const Uuid().v4();
      await _store.save(attachmentId, bytes);
      final DateTime now = DateTime.now();
      final NoteCard card = await _repo.createCard(
        notebookId: widget.notebookId,
        type: CardType.voice,
        title: 'Voice note, ${formatStamp(now)}',
        colorIndex: 4,
        attachments: <Attachment>[
          Attachment(
            id: attachmentId,
            kind: AttachmentKind.audio,
            fileName: 'voice-${now.millisecondsSinceEpoch}.$_extension',
            byteLength: bytes.length,
            durationMs: elapsed.inMilliseconds,
          ),
        ],
      );
      if (!mounted) {
        return;
      }
      context.pushReplacement('/card/${card.id}');
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _phase = _Phase.failed;
        _error = 'The recording could not be saved. Please try again.';
      });
    }
  }

  Future<bool> _confirmDiscard() async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Discard this recording?'),
          content: const Text('The recording is deleted and cannot be brought back.'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep recording'),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: VarnaColors.of(dialogContext).danger,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Discard'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _discard() async {
    if (_phase == _Phase.saving) {
      return;
    }
    final bool active = _phase == _Phase.recording || _phase == _Phase.paused;
    if (active && _watch.elapsed > const Duration(seconds: 3)) {
      final bool ok = await _confirmDiscard();
      if (!ok || !mounted) {
        return;
      }
    }
    _ticker?.cancel();
    unawaited(_ampSub?.cancel());
    try {
      await _recorder.cancel();
    } catch (_) {
      // Already stopped.
    }
    if (!mounted) {
      return;
    }
    leaveScreen(context);
  }

  // ------------------------------------------------------------------- build

  String get _phaseLabel {
    switch (_phase) {
      case _Phase.starting:
        return 'Getting ready';
      case _Phase.recording:
        return 'Recording';
      case _Phase.paused:
        return 'Paused';
      case _Phase.saving:
        return 'Saving';
      case _Phase.denied:
      case _Phase.failed:
        return 'Voice note';
    }
  }

  @override
  Widget build(BuildContext context) {
    final VarnaColors colors = VarnaColors.of(context);
    final String? notebookName =
        ref.watch(notebookProvider(widget.notebookId)).value?.title;
    final bool busy = _phase == _Phase.recording ||
        _phase == _Phase.paused ||
        _phase == _Phase.saving;

    final Widget header = Row(
      children: <Widget>[
        RoundIconButton(
          icon: Icons.close,
          tooltip: busy ? 'Discard recording and close' : 'Close',
          onPressed: _phase == _Phase.saving ? null : () => unawaited(_discard()),
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _phase == _Phase.recording
                      ? colors.danger
                      : colors.ink.withValues(alpha: 0.35),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _phaseLabel,
                  overflow: TextOverflow.ellipsis,
                  style: bodyStyle(context, 14, weight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 44),
      ],
    );

    Widget bodyFor(bool roomy) {
      if (_phase == _Phase.denied) {
        return _MessageBody(
          icon: Icons.mic_off_outlined,
          title: 'Microphone access is off',
          message: 'Varna needs the microphone to record voice notes. Allow '
              'it for ${AppConfig.appName} in your phone settings, then try '
              'again.',
          onRetry: () => unawaited(_retry()),
          onBack: () => leaveScreen(context),
        );
      }
      if (_phase == _Phase.failed) {
        return _MessageBody(
          icon: Icons.error_outline,
          title: 'Could not record',
          message: _error ?? 'Something went wrong. Please try again.',
          onRetry: () => unawaited(_retry()),
          onBack: () => leaveScreen(context),
        );
      }
      return _RecordingBody(
        roomy: roomy,
        elapsed: _watch.elapsed,
        levels: _levels,
        phase: _phase,
        caption: notebookName == null || notebookName.isEmpty
            ? 'Stop saves the card to this notebook'
            : 'Stop saves the card to $notebookName',
        onDiscard: () => unawaited(_discard()),
        onStop: () => unawaited(_stopAndSave()),
        onTogglePause: () => unawaited(_togglePause()),
      );
    }

    return PopScope(
      canPop: !busy,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) {
          unawaited(_discard());
        }
      },
      child: Scaffold(
        backgroundColor: colors.cardColor(4),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints box) {
                  // On short screens (landscape) everything scrolls instead
                  // of being squeezed.
                  final bool roomy = box.maxHeight >= 600;
                  if (roomy) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          header,
                          Expanded(child: bodyFor(true)),
                        ],
                      ),
                    );
                  }
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[header, bodyFor(false)],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecordingBody extends StatelessWidget {
  const _RecordingBody({
    required this.roomy,
    required this.elapsed,
    required this.levels,
    required this.phase,
    required this.caption,
    required this.onDiscard,
    required this.onStop,
    required this.onTogglePause,
  });

  final bool roomy;
  final Duration elapsed;
  final List<double> levels;
  final _Phase phase;
  final String caption;
  final VoidCallback onDiscard;
  final VoidCallback onStop;
  final VoidCallback onTogglePause;

  @override
  Widget build(BuildContext context) {
    final VarnaColors colors = VarnaColors.of(context);
    final bool saving = phase == _Phase.saving;
    final bool starting = phase == _Phase.starting;
    final bool paused = phase == _Phase.paused;
    final bool canAct = phase == _Phase.recording || paused;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 36),
        Semantics(
          label: 'Recording time ${formatTimer(elapsed)}',
          child: ExcludeSemantics(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                formatTimer(elapsed),
                style: displayStyle(context, 76).copyWith(
                  letterSpacing: -2,
                  color: colors.ink,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _LevelBars(levels: levels, paused: paused || starting),
        const SizedBox(height: 20),
        if (saving)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text(
                'Saving your voice note...',
                style: bodyStyle(context, 15, weight: FontWeight.w600),
              ),
            ],
          )
        else if (starting)
          Text(
            'Getting the microphone ready...',
            textAlign: TextAlign.center,
            style: bodyStyle(context, 15, weight: FontWeight.w600),
          ),
        if (roomy) const Spacer() else const SizedBox(height: 32),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              _CircleButton(
                size: 60,
                tooltip: 'Discard recording',
                onPressed: canAct ? onDiscard : null,
                background: frostedWhite(),
                child: Icon(Icons.delete_outline, size: 26, color: colors.ink),
              ),
              _CircleButton(
                size: 88,
                tooltip: 'Stop and save',
                onPressed: canAct ? onStop : null,
                background: colors.ink,
                shadow: true,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
              ),
              _CircleButton(
                size: 60,
                tooltip: paused ? 'Resume recording' : 'Pause recording',
                onPressed: canAct ? onTogglePause : null,
                background: frostedWhite(),
                child: Icon(
                  paused ? Icons.mic : Icons.pause,
                  size: 26,
                  color: colors.ink,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          caption,
          textAlign: TextAlign.center,
          style: bodyStyle(context, 14, weight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.size,
    required this.tooltip,
    required this.onPressed,
    required this.background,
    required this.child,
    this.shadow = false,
  });

  final double size;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color background;
  final bool shadow;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final VarnaColors colors = VarnaColors.of(context);
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: tooltip,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        child: Opacity(
          opacity: onPressed == null ? 0.5 : 1,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: shadow
                  ? <BoxShadow>[
                      BoxShadow(
                        color: colors.ink.withValues(alpha: 0.30),
                        blurRadius: 26,
                        offset: const Offset(0, 12),
                      ),
                    ]
                  : null,
            ),
            child: Material(
              color: background,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onPressed,
                child: Center(child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LevelBars extends StatelessWidget {
  const _LevelBars({required this.levels, required this.paused});

  final List<double> levels;
  final bool paused;

  @override
  Widget build(BuildContext context) {
    final VarnaColors colors = VarnaColors.of(context);
    return SizedBox(
      height: 120,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) {
            final int fit = ((box.maxWidth + 5) / 10).floor();
            final int slots = fit < 8 ? 8 : (fit > 48 ? 48 : fit);
            final int first = math.max(0, levels.length - slots);
            final List<double> shown = levels.sublist(first);
            final List<Widget> bars = <Widget>[];
            for (int i = 0; i < slots; i++) {
              if (i > 0) {
                bars.add(const SizedBox(width: 5));
              }
              final bool filled = i < shown.length;
              final double level = filled ? shown[i] : 0;
              bars.add(
                AnimatedContainer(
                  duration: const Duration(milliseconds: 110),
                  width: 5,
                  height: 10 + level * 100,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: filled && !paused
                        ? colors.ink
                        : colors.ink.withValues(alpha: 0.3),
                  ),
                ),
              );
            }
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: bars,
            );
          },
        ),
      ),
    );
  }
}

class _MessageBody extends StatelessWidget {
  const _MessageBody({
    required this.icon,
    required this.title,
    required this.message,
    required this.onRetry,
    required this.onBack,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final VarnaColors colors = VarnaColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Icon(icon, size: 56, color: colors.ink),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: displayStyle(context, 26),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: bodyStyle(context, 16, height: 1.45),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
            const SizedBox(height: 10),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                backgroundColor: frostedWhite(),
              ),
              onPressed: onBack,
              child: const Text('Go back'),
            ),
          ],
        ),
      ),
    );
  }
}
