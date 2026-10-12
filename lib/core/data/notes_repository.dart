import 'dart:async';
import 'dart:math' as math;

import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import '../clock.dart';
import '../models/models.dart';
import 'attachment_store.dart';

typedef _Snap = RecordSnapshot<String, Map<String, Object?>>;

/// Local persistence of notebooks, cards, sync bookkeeping and conflicts.
///
/// Conventions:
/// * Every write through the public create/update/delete methods bumps
///   `updatedAt` (strictly increasing per record) and so marks the record as
///   changed since its last sync (dirty = no [SyncState] or
///   `state.lastSyncedLocalUpdatedAt != record.updatedAt`).
/// * Deletes are soft: the record stays as a tombstone (`deleted == true`,
///   content blanked) so the delete can sync. All `list*`/`watch*` methods
///   hide tombstones.
/// * Notebooks are sorted by `createdAt` ascending, cards by `updatedAt`
///   descending.
class NotesRepository {
  NotesRepository(
    this._db, {
    Clock? clock,
    Uuid? uuid,
    AttachmentStore? attachments,
  })  : _clock = clock ?? systemClock,
        _uuid = uuid ?? Uuid(),
        _attachments = attachments;

  final Database _db;
  final Clock _clock;
  final Uuid _uuid;
  final AttachmentStore? _attachments;

  final StoreRef<String, Map<String, Object?>> _notebooks =
      stringMapStoreFactory.store('notebooks');
  final StoreRef<String, Map<String, Object?>> _cards =
      stringMapStoreFactory.store('cards');
  final StoreRef<String, Map<String, Object?>> _syncStates =
      stringMapStoreFactory.store('sync_state');
  final StoreRef<String, Map<String, Object?>> _conflicts =
      stringMapStoreFactory.store('sync_conflicts');

  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Fires after every local write (create/update/delete, duplicate). Not
  /// fired for changes applied from the cloud. The sync controller listens to
  /// this to schedule an automatic sync.
  Stream<void> get changes => _changes.stream;

  void _notify() {
    if (!_changes.isClosed) {
      _changes.add(null);
    }
  }

  /// Releases the [changes] stream. The database is closed by its owner.
  Future<void> dispose() => _changes.close();

  DateTime _stamp([DateTime? previous]) {
    final DateTime now = _clock().toUtc();
    if (previous != null && !now.isAfter(previous)) {
      return previous.add(const Duration(milliseconds: 1));
    }
    return now;
  }

  // ---------------------------------------------------------------- notebooks

  Notebook _toNotebook(_Snap s) => Notebook.fromJson(s.value);
  NoteCard _toCard(_Snap s) => NoteCard.fromJson(s.value);

  List<Notebook> _liveNotebooks(List<_Snap> snaps) {
    final List<Notebook> list = snaps
        .map(_toNotebook)
        .where((Notebook n) => !n.deleted)
        .toList()
      ..sort((Notebook a, Notebook b) {
        final int c = a.createdAt.compareTo(b.createdAt);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    return list;
  }

  List<NoteCard> _sortedCards(Iterable<NoteCard> cards) {
    final List<NoteCard> list = cards.toList()
      ..sort((NoteCard a, NoteCard b) {
        final int c = b.updatedAt.compareTo(a.updatedAt);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    return list;
  }

  /// Live (non-deleted) notebooks; emits the current value first, then on
  /// every change.
  Stream<List<Notebook>> watchNotebooks() {
    return _notebooks
        .query()
        .onSnapshots(_db)
        .map((List<_Snap> snaps) => _liveNotebooks(snaps));
  }

  /// One notebook, or null when missing/deleted.
  Stream<Notebook?> watchNotebook(String id) {
    return _notebooks.record(id).onSnapshot(_db).map((_Snap? s) {
      if (s == null) {
        return null;
      }
      final Notebook n = _toNotebook(s);
      return n.deleted ? null : n;
    });
  }

  Future<List<Notebook>> listNotebooks() async {
    return _liveNotebooks(await _notebooks.find(_db));
  }

  /// Number of live notebooks (used for the free-plan limit).
  Future<int> countNotebooks() async => (await listNotebooks()).length;

  /// The notebook, or null when missing/deleted.
  Future<Notebook?> getNotebook(String id) async {
    final Map<String, Object?>? v = await _notebooks.record(id).get(_db);
    if (v == null) {
      return null;
    }
    final Notebook n = Notebook.fromJson(v);
    return n.deleted ? null : n;
  }

  Future<Notebook> createNotebook({
    required String title,
    int colorIndex = 0,
    bool locked = false,
  }) async {
    final DateTime now = _stamp();
    final Notebook nb = Notebook(
      id: _uuid.v4(),
      title: title,
      colorIndex: colorIndex,
      locked: locked,
      createdAt: now,
      updatedAt: now,
    );
    await _notebooks.record(nb.id).put(_db, nb.toJson());
    _notify();
    return nb;
  }

  /// Saves [notebook] (keeping the stored `createdAt`), bumps `updatedAt` and
  /// returns the saved value.
  Future<Notebook> updateNotebook(Notebook notebook) async {
    final Map<String, Object?>? raw = await _notebooks.record(notebook.id).get(_db);
    final Notebook? existing = raw == null ? null : Notebook.fromJson(raw);
    final Notebook next = notebook.copyWith(
      createdAt: existing?.createdAt ?? notebook.createdAt,
      updatedAt: _stamp(existing?.updatedAt),
    );
    await _notebooks.record(next.id).put(_db, next.toJson());
    _notify();
    return next;
  }

  /// Soft-deletes the notebook and all its cards (tombstones, content
  /// blanked). Attachment bytes of those cards are removed from the local
  /// attachment store when one was supplied to the constructor.
  Future<void> deleteNotebook(String id) async {
    final List<Attachment> orphaned = <Attachment>[];
    await _db.transaction((Transaction txn) async {
      final Map<String, Object?>? raw = await _notebooks.record(id).get(txn);
      if (raw != null) {
        final Notebook nb = Notebook.fromJson(raw);
        if (!nb.deleted) {
          final Notebook dead = nb.copyWith(
            title: '',
            deleted: true,
            updatedAt: _stamp(nb.updatedAt),
          );
          await _notebooks.record(id).put(txn, dead.toJson());
        }
      }
      final List<_Snap> snaps = await _cards.find(txn);
      for (final _Snap s in snaps) {
        final NoteCard card = _toCard(s);
        if (card.notebookId == id && !card.deleted) {
          orphaned.addAll(card.attachments);
          await _cards.record(card.id).put(txn, _tombstone(card).toJson());
        }
      }
    });
    await _dropAttachments(orphaned);
    _notify();
  }

  // -------------------------------------------------------------------- cards

  Stream<List<NoteCard>> _watchCardsWhere(bool Function(NoteCard) test) {
    return _cards.query().onSnapshots(_db).map((List<_Snap> snaps) {
      return _sortedCards(
        snaps.map(_toCard).where((NoteCard c) => !c.deleted && test(c)),
      );
    });
  }

  /// Live cards of one notebook, newest change first.
  Stream<List<NoteCard>> watchCards(String notebookId) =>
      _watchCardsWhere((NoteCard c) => c.notebookId == notebookId);

  /// All favourite cards across notebooks, newest change first.
  Stream<List<NoteCard>> watchFavourites() =>
      _watchCardsWhere((NoteCard c) => c.favourite);

  /// Cards with an `expiryDate`, soonest first (overdue ones come first).
  /// Feed this to `RenewalsLogic.upcoming` to get labels.
  Stream<List<NoteCard>> watchUpcomingRenewals() {
    return _cards.query().onSnapshots(_db).map((List<_Snap> snaps) {
      return _renewals(snaps.map(_toCard));
    });
  }

  List<NoteCard> _renewals(Iterable<NoteCard> cards) {
    final List<NoteCard> list = cards
        .where((NoteCard c) => !c.deleted && c.expiryDate != null)
        .toList()
      ..sort((NoteCard a, NoteCard b) {
        final int c = a.expiryDate!.compareTo(b.expiryDate!);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    return list;
  }

  /// One card, or null when missing/deleted.
  Stream<NoteCard?> watchCard(String id) {
    return _cards.record(id).onSnapshot(_db).map((_Snap? s) {
      if (s == null) {
        return null;
      }
      final NoteCard c = _toCard(s);
      return c.deleted ? null : c;
    });
  }

  Future<List<NoteCard>> _allCards() async {
    final List<_Snap> snaps = await _cards.find(_db);
    return snaps.map(_toCard).toList();
  }

  Future<List<NoteCard>> listCards(String notebookId) async {
    final List<NoteCard> all = await _allCards();
    return _sortedCards(
      all.where((NoteCard c) => !c.deleted && c.notebookId == notebookId),
    );
  }

  Future<List<NoteCard>> listFavourites() async {
    final List<NoteCard> all = await _allCards();
    return _sortedCards(all.where((NoteCard c) => !c.deleted && c.favourite));
  }

  Future<List<NoteCard>> listUpcomingRenewals() async {
    return _renewals(await _allCards());
  }

  /// Every live card (all notebooks), newest change first.
  Future<List<NoteCard>> listAllCards() async {
    final List<NoteCard> all = await _allCards();
    return _sortedCards(all.where((NoteCard c) => !c.deleted));
  }

  /// The card, or null when missing/deleted.
  Future<NoteCard?> getCard(String id) async {
    final Map<String, Object?>? v = await _cards.record(id).get(_db);
    if (v == null) {
      return null;
    }
    final NoteCard c = NoteCard.fromJson(v);
    return c.deleted ? null : c;
  }

  Future<NoteCard> createCard({
    required String notebookId,
    required CardType type,
    String title = '',
    String body = '',
    int colorIndex = 0,
    List<ChecklistItem> items = const <ChecklistItem>[],
    List<Attachment> attachments = const <Attachment>[],
    String? ocrText,
    String? transcript,
    bool favourite = false,
    DateTime? reminderAt,
    DateTime? expiryDate,
    String? paperFolder,
  }) async {
    final DateTime now = _stamp();
    final NoteCard card = NoteCard(
      id: _uuid.v4(),
      notebookId: notebookId,
      type: type,
      title: title,
      body: body,
      colorIndex: colorIndex,
      items: items,
      attachments: attachments,
      ocrText: ocrText,
      transcript: transcript,
      favourite: favourite,
      reminderAt: reminderAt,
      expiryDate: expiryDate,
      paperFolder: paperFolder,
      createdAt: now,
      updatedAt: now,
    );
    await _cards.record(card.id).put(_db, card.toJson());
    _notify();
    return card;
  }

  /// Saves [card] (keeping the stored `createdAt`), bumps `updatedAt` and
  /// returns the saved value. Use `card.copyWith(...)` to make changes.
  Future<NoteCard> updateCard(NoteCard card) async {
    final Map<String, Object?>? raw = await _cards.record(card.id).get(_db);
    final NoteCard? existing = raw == null ? null : NoteCard.fromJson(raw);
    final NoteCard next = card.copyWith(
      createdAt: existing?.createdAt ?? card.createdAt,
      updatedAt: _stamp(existing?.updatedAt),
    );
    await _cards.record(next.id).put(_db, next.toJson());
    _notify();
    return next;
  }

  /// Soft-deletes a card: it becomes a tombstone with its content blanked, and
  /// its attachment bytes are removed from the local store (when one was
  /// supplied to the constructor).
  Future<void> deleteCard(String id) async {
    final Map<String, Object?>? raw = await _cards.record(id).get(_db);
    if (raw == null) {
      return;
    }
    final NoteCard card = NoteCard.fromJson(raw);
    if (card.deleted) {
      return;
    }
    await _cards.record(id).put(_db, _tombstone(card).toJson());
    await _dropAttachments(card.attachments);
    _notify();
  }

  NoteCard _tombstone(NoteCard card) {
    return NoteCard(
      id: card.id,
      notebookId: card.notebookId,
      type: card.type,
      createdAt: card.createdAt,
      updatedAt: _stamp(card.updatedAt),
      deleted: true,
    );
  }

  Future<void> _dropAttachments(List<Attachment> list) async {
    final AttachmentStore? store = _attachments;
    if (store == null) {
      return;
    }
    for (final Attachment a in list) {
      try {
        await store.delete(a.id);
      } catch (_) {
        // Best effort: a leftover blob is harmless.
      }
    }
  }

  // ------------------------------------------------------------------- search

  /// Case-insensitive search over title, body, checklist item texts,
  /// `ocrText` and `transcript` of live cards. A query with several words
  /// matches cards containing every word (anywhere). Results are ordered by
  /// the best field that matched (title first), then newest change first.
  /// An empty query returns an empty list.
  Future<List<SearchHit>> search(
    String query, {
    CardType? type,
    int limit = 100,
  }) async {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return const <SearchHit>[];
    }
    final List<String> terms =
        q.split(RegExp(r'\s+')).where((String t) => t.isNotEmpty).toList();
    final List<NoteCard> cards = await _allCards();
    final List<SearchHit> hits = <SearchHit>[];
    for (final NoteCard card in cards) {
      if (card.deleted || (type != null && card.type != type)) {
        continue;
      }
      final Map<SearchField, String> fields = <SearchField, String>{
        SearchField.title: card.title,
        SearchField.body: card.body,
        SearchField.items:
            card.items.map((ChecklistItem i) => i.text).join('\n'),
        SearchField.ocrText: card.ocrText ?? '',
        SearchField.transcript: card.transcript ?? '',
      };
      final String combined = fields.values.join('\n').toLowerCase();
      if (!terms.every(combined.contains)) {
        continue;
      }
      final List<SearchField> matched = <SearchField>[];
      for (final SearchField f in SearchField.values) {
        final String lower = fields[f]!.toLowerCase();
        if (terms.any(lower.contains)) {
          matched.add(f);
        }
      }
      if (matched.isEmpty) {
        continue;
      }
      final SearchField primary = matched.first;
      final String text = fields[primary]!;
      final String lower = text.toLowerCase();
      int index = -1;
      int length = 0;
      for (final String t in terms) {
        final int i = lower.indexOf(t);
        if (i >= 0 && (index < 0 || i < index)) {
          index = i;
          length = t.length;
        }
      }
      hits.add(SearchHit(
        card: card,
        matchedIn: primary,
        matchedFields: matched,
        snippet: makeSnippet(text, index, length),
      ));
    }
    hits.sort((SearchHit a, SearchHit b) {
      final int c = a.matchedIn.index.compareTo(b.matchedIn.index);
      if (c != 0) {
        return c;
      }
      return b.card.updatedAt.compareTo(a.card.updatedAt);
    });
    return hits.length > limit ? hits.sublist(0, limit) : hits;
  }

  /// Builds a one-line excerpt of [text] around [index] (the match start) with
  /// "..." where it was cut. Exposed for tests.
  static String makeSnippet(String text, int index, int matchLength) {
    const int before = 28;
    const int after = 72;
    final int safeIndex = math.max(0, math.min(index, text.length));
    final int start = math.max(0, safeIndex - before);
    final int end = math.min(text.length, safeIndex + matchLength + after);
    String s = text.substring(start, end).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (start > 0) {
      s = '...$s';
    }
    if (end < text.length) {
      s = '$s...';
    }
    return s;
  }

  // ------------------------------------------------------------ sync surface
  //
  // Used by the sync engine; the UI normally does not call these.

  /// Every notebook and card, including tombstones.
  Future<List<SyncRecord>> allSyncRecords() async {
    final List<SyncRecord> out = <SyncRecord>[];
    for (final _Snap s in await _notebooks.find(_db)) {
      out.add(SyncRecord.fromNotebook(_toNotebook(s)));
    }
    for (final _Snap s in await _cards.find(_db)) {
      out.add(SyncRecord.fromCard(_toCard(s)));
    }
    return out;
  }

  StoreRef<String, Map<String, Object?>> _storeFor(RecordKind kind) =>
      kind == RecordKind.notebook ? _notebooks : _cards;

  /// The record (tombstones included), or null.
  Future<SyncRecord?> getSyncRecord(RecordKind kind, String id) async {
    final Map<String, Object?>? v = await _storeFor(kind).record(id).get(_db);
    return v == null ? null : SyncRecord.fromJson(kind, v);
  }

  /// Stores a record received from the cloud, without bumping `updatedAt`
  /// and without marking it dirty.
  Future<void> applyRemoteRecord(SyncRecord record) async {
    final SyncRecord normalised = SyncRecord.fromJson(record.kind, record.json);
    await _storeFor(record.kind).record(record.id).put(_db, normalised.json);
  }

  /// Gives the record a fresh `updatedAt` (so it counts as changed) and returns
  /// it. Used when the user resolves a conflict with "keep local".
  Future<SyncRecord?> touchRecord(RecordKind kind, String id) async {
    final SyncRecord? current = await getSyncRecord(kind, id);
    if (current == null) {
      return null;
    }
    final Map<String, Object?> json = Map<String, Object?>.of(current.json);
    json['updatedAt'] = formatUtc(_stamp(current.updatedAt));
    final SyncRecord next = SyncRecord.fromJson(kind, json);
    await _storeFor(kind).record(id).put(_db, next.json);
    return next;
  }

  /// Saves a copy of [record] under a new id, titled "<title> (copy)". Returns
  /// the new id. The copy is dirty and uploads on the next sync.
  Future<String> duplicateRecord(SyncRecord record) async {
    final DateTime now = _stamp();
    final String newId = _uuid.v4();
    final Map<String, Object?> json = Map<String, Object?>.of(record.json);
    json['id'] = newId;
    json['createdAt'] = formatUtc(now);
    json['updatedAt'] = formatUtc(now);
    json['deleted'] = false;
    final String title = (json['title'] as String?) ?? '';
    json['title'] = title.isEmpty ? '(copy)' : '$title (copy)';
    final SyncRecord copy = SyncRecord.fromJson(record.kind, json);
    await _storeFor(record.kind).record(newId).put(_db, copy.json);
    _notify();
    return newId;
  }

  /// Number of records that changed locally since their last sync.
  Future<int> countUnsynced() async {
    final List<SyncRecord> records = await allSyncRecords();
    int count = 0;
    for (final SyncRecord r in records) {
      final SyncState? s = await getSyncState(r.key);
      if (s == null || s.lastSyncedLocalUpdatedAt != r.updatedAt) {
        count++;
      }
    }
    return count;
  }

  Future<SyncState?> getSyncState(String key) async {
    final Map<String, Object?>? v = await _syncStates.record(key).get(_db);
    return v == null ? null : SyncState.fromJson(v);
  }

  Future<void> putSyncState(SyncState state) async {
    await _syncStates.record(state.key).put(_db, state.toJson());
  }

  Future<List<SyncState>> allSyncStates() async {
    final List<_Snap> snaps = await _syncStates.find(_db);
    return snaps.map((_Snap s) => SyncState.fromJson(s.value)).toList();
  }

  Future<void> clearSyncStates() async {
    await _syncStates.delete(_db);
  }

  /// Replaces all sync states with [states].
  Future<void> replaceSyncStates(List<SyncState> states) async {
    await _db.transaction((Transaction txn) async {
      await _syncStates.delete(txn);
      for (final SyncState s in states) {
        await _syncStates.record(s.key).put(txn, s.toJson());
      }
    });
  }

  // ---------------------------------------------------------------- conflicts

  /// Open conflicts, oldest first.
  Future<List<SyncConflict>> listConflicts() async {
    return _sortedConflicts(await _conflicts.find(_db));
  }

  Stream<List<SyncConflict>> watchConflicts() {
    return _conflicts
        .query()
        .onSnapshots(_db)
        .map((List<_Snap> snaps) => _sortedConflicts(snaps));
  }

  List<SyncConflict> _sortedConflicts(List<_Snap> snaps) {
    final List<SyncConflict> list = snaps
        .map((_Snap s) => SyncConflict.fromJson(s.value))
        .toList()
      ..sort((SyncConflict a, SyncConflict b) {
        final int c = a.detectedAt.compareTo(b.detectedAt);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    return list;
  }

  /// The open conflict for a notebook/card id, or null.
  Future<SyncConflict?> getConflict(String id) async {
    final Map<String, Object?>? v = await _conflicts.record(id).get(_db);
    return v == null ? null : SyncConflict.fromJson(v);
  }

  Future<void> putConflict(SyncConflict conflict) async {
    await _conflicts.record(conflict.id).put(_db, conflict.toJson());
  }

  Future<void> removeConflict(String id) async {
    await _conflicts.record(id).delete(_db);
  }

  Future<void> clearConflicts() async {
    await _conflicts.delete(_db);
  }
}
