import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/data/notes_repository.dart';
import '../../../../core/models/models.dart';

/// Writes changes to one card. Every change is applied to the *latest stored*
/// version of the card (never to a stale copy held by a screen), and changes
/// are applied strictly one after another. A card that was deleted in the
/// meantime is left alone (it is never resurrected).
class CardSaver {
  CardSaver(this._repository, this.cardId);

  final NotesRepository _repository;
  final String cardId;

  Future<void> _chain = Future<void>.value();

  /// Applies [change] to the stored card and saves it when something changed.
  /// Resolves to the saved card, or null when the card no longer exists.
  Future<NoteCard?> update(NoteCard Function(NoteCard card) change) {
    final Future<NoteCard?> result = _chain.then<NoteCard?>((_) async {
      final NoteCard? current = await _repository.getCard(cardId);
      if (current == null) {
        return null;
      }
      final NoteCard changed = change(current);
      if (changed == current) {
        return current;
      }
      return _repository.updateCard(changed);
    });
    _chain = result.then<void>((NoteCard? _) {}, onError: (Object _) {});
    return result;
  }
}

/// Save progress shown in the card header.
enum SaveStatus { saved, saving, failed }

/// Debounced autosave. Call [markChanged] on every edit; [onSave] runs
/// [delay] after the last edit (or immediately on [flush]). [dispose] saves
/// anything still pending, so edits are never lost when the screen closes.
///
/// [onSave] must read the current field values synchronously before its first
/// `await` (it is called while the screen is being torn down).
class Autosaver {
  Autosaver({
    required Future<void> Function() onSave,
    this.delay = const Duration(milliseconds: 600),
  }) : _onSave = onSave;

  final Future<void> Function() _onSave;
  final Duration delay;

  /// What the header should show.
  final ValueNotifier<SaveStatus> status =
      ValueNotifier<SaveStatus>(SaveStatus.saved);

  Timer? _timer;
  bool _dirty = false;
  bool _disposed = false;
  int _inFlight = 0;

  /// True when there are edits that are not yet saved.
  bool get hasPendingChanges => _dirty;

  /// True while a save is running.
  bool get isSaving => _inFlight > 0;

  void markChanged() {
    if (_disposed) {
      return;
    }
    _dirty = true;
    status.value = SaveStatus.saving;
    _timer?.cancel();
    _timer = Timer(delay, () {
      unawaited(flush());
    });
  }

  /// Saves now when there is something to save.
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    if (!_dirty) {
      return;
    }
    _dirty = false;
    _inFlight++;
    try {
      await _onSave();
    } catch (_) {
      _dirty = true;
      if (!_disposed) {
        status.value = SaveStatus.failed;
      }
      return;
    } finally {
      _inFlight--;
    }
    if (!_disposed && !_dirty && _inFlight == 0) {
      status.value = SaveStatus.saved;
    }
  }

  /// Saves pending edits (without waiting) and releases resources.
  void dispose() {
    if (_disposed) {
      return;
    }
    _timer?.cancel();
    _timer = null;
    final bool pending = _dirty;
    _dirty = false;
    _disposed = true;
    if (pending) {
      unawaited(
        Future<void>.sync(_onSave).catchError((Object _) {}),
      );
    }
    status.dispose();
  }
}
