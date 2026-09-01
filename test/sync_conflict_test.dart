import 'package:flutter_test/flutter_test.dart';
import 'package:marley/data/gist_sync_service.dart';
import 'package:marley/data/storage_service.dart';
import 'package:marley/models/app_data.dart';
import 'package:marley/state/app_state.dart';

/// Never touches SharedPreferences, so these tests don't depend on a
/// platform channel being mocked. Both boxes are plain in-memory slots
/// rather than fields on the instance so tests can simulate an app
/// restart: build a second `_NoopStorage` pointed at the same boxes and a
/// fresh `AppState` on top of it, and see whether the persisted values
/// survived — exactly what `SharedPreferences` would do for real.
class _NoopStorage extends StorageService {
  _NoopStorage({List<int?>? lastSyncedTsBox, List<AppData?>? dataBox})
      : _lastSyncedTsBox = lastSyncedTsBox ?? [null],
        _dataBox = dataBox ?? [null];

  final List<int?> _lastSyncedTsBox;
  final List<AppData?> _dataBox;

  @override
  Future<AppData?> load() async => _dataBox[0];
  @override
  Future<void> save(AppData data) async {
    _dataBox[0] = data;
  }

  @override
  Future<int?> loadLastSyncedTs() async => _lastSyncedTsBox[0];
  @override
  Future<void> saveLastSyncedTs(int ts) async {
    _lastSyncedTsBox[0] = ts;
  }
}

/// Stands in for the network: lets tests control exactly what "the server"
/// currently has, and records every push without touching HTTP or secure
/// storage.
class _FakeGistSync extends GistSyncService {
  bool credentialsPresent = true;
  AppData? remoteData;
  int pushCount = 0;
  AppData? lastPushed;

  @override
  Future<bool> hasCredentials() async => credentialsPresent;

  @override
  Future<AppData?> fetchRemote() async => remoteData;

  @override
  Future<int?> fetchRemoteLastModified() async => remoteData?.lastModified;

  @override
  Future<void> pushData(AppData data) async {
    pushCount++;
    lastPushed = data;
  }
}

AppData _dataAt(int ts) {
  const month = '2026-08';
  return AppData(
    lastModified: ts,
    months: const [month],
    balances: const Balances(),
    txns: const [],
    budgets: const {month: {}},
    goals: const {},
  );
}

void main() {
  group('trySync conflict detection', () {
    test('pushes when there is nothing on the server yet', () async {
      final fake = _FakeGistSync()..remoteData = null;
      final appState = AppState(storage: _NoopStorage(), gistSync: fake);

      await appState.trySync();

      expect(fake.pushCount, 1);
      expect(appState.pendingConflict, isNull);
      expect(appState.syncStatus, SyncStatus.idle);
    });

    test('adopts remote outright when it is strictly newer than local',
        () async {
      final remote = _dataAt(2000);
      final fake = _FakeGistSync()..remoteData = remote;
      final appState = AppState(storage: _NoopStorage(), gistSync: fake);

      await appState.trySync();

      expect(appState.data.lastModified, 2000);
      expect(fake.pushCount, 0);
      expect(appState.pendingConflict, isNull);
    });

    test('pushes when the remote has not moved since our last known sync point',
        () async {
      final fake = _FakeGistSync()..remoteData = _dataAt(500);
      final appState = AppState(storage: _NoopStorage(), gistSync: fake);
      await appState.trySync(); // adopts remote@500, _lastSyncedTs = 500
      expect(appState.data.lastModified, 500);

      await appState
          .updateBalances(const Balances(rev: 99)); // local moves ahead
      expect(appState.data.lastModified, greaterThan(500));

      await appState.trySync(); // remote is still exactly what we last saw

      expect(fake.pushCount, 1);
      expect(appState.pendingConflict, isNull);
    });

    test(
        'byte-identical remote and local is never a conflict, even on a '
        'fresh session that never synced before', () async {
      // Reproduces the false-positive that used to pop the conflict dialog
      // on every single cold start: `_lastSyncedTs` starts at 0 for a
      // brand-new AppState, and back when the only check was
      // `remote.lastModified > _lastSyncedTs`, any nonzero remote ts (i.e.
      // basically always) looked like "the remote moved since we last
      // looked" — even when remote and local were the exact same data.
      final fake = _FakeGistSync();
      final appState = AppState(storage: _NoopStorage(), gistSync: fake);
      await appState.updateBalances(const Balances(rev: 42)); // local moves
      fake.remoteData = _dataAt(appState.data.lastModified); // ...and so did "the server", to the exact same value

      await appState.trySync();

      expect(appState.pendingConflict, isNull);
      expect(fake.pushCount, 0); // already identical, nothing to push
    });

    test('flags a conflict instead of guessing when both sides diverged',
        () async {
      final fake = _FakeGistSync()..remoteData = _dataAt(500);
      final appState = AppState(storage: _NoopStorage(), gistSync: fake);
      await appState.trySync(); // catches up to remote@500
      await appState
          .updateBalances(const Balances(rev: 99)); // local moves past 500

      // Someone else also pushed since our last known sync point (500),
      // but that new remote value is still older than local's current ts —
      // this is exactly the shape of bug that silently overwrote a week of
      // data on the web app: local "looks newer" by raw comparison even
      // though the remote moved too.
      fake.remoteData = _dataAt(appState.data.lastModified - 1);

      await appState.trySync();

      expect(appState.pendingConflict, isNotNull);
      expect(fake.pushCount, 0); // must not have silently pushed over it
    });

    test('resolveConflictKeepLocal pushes local and clears the conflict',
        () async {
      final fake = _FakeGistSync()..remoteData = _dataAt(500);
      final appState = AppState(storage: _NoopStorage(), gistSync: fake);
      await appState.trySync();
      await appState.updateBalances(const Balances(rev: 5));
      fake.remoteData = _dataAt(appState.data.lastModified - 1);
      await appState.trySync();
      expect(appState.pendingConflict, isNotNull);

      await appState.resolveConflictKeepLocal();

      expect(appState.pendingConflict, isNull);
      expect(fake.pushCount, 1);
      expect(fake.lastPushed?.lastModified, appState.data.lastModified);
    });

    test('resolveConflictUseRemote adopts remote and clears the conflict',
        () async {
      final fake = _FakeGistSync()..remoteData = _dataAt(500);
      final appState = AppState(storage: _NoopStorage(), gistSync: fake);
      await appState.trySync();
      await appState.updateBalances(const Balances(rev: 5));
      final conflictingRemote = _dataAt(appState.data.lastModified - 1);
      fake.remoteData = conflictingRemote;
      await appState.trySync();
      expect(appState.pendingConflict, isNotNull);

      await appState.resolveConflictUseRemote();

      expect(appState.pendingConflict, isNull);
      expect(appState.data.lastModified, conflictingRemote.lastModified);
      expect(fake.pushCount, 0);
    });
  });

  group('pushIfDirty background guard', () {
    test('does nothing if this session never verified the remote', () async {
      final fake = _FakeGistSync();
      final appState = AppState(storage: _NoopStorage(), gistSync: fake);
      await appState.updateBalances(const Balances(rev: 1));

      await appState.pushIfDirty();

      expect(fake.pushCount, 0);
    });

    test('backs off if the remote moved since our last known sync point',
        () async {
      final fake = _FakeGistSync()..remoteData = _dataAt(500);
      final appState = AppState(storage: _NoopStorage(), gistSync: fake);
      await appState
          .trySync(); // _hasSyncedThisSession = true, _lastSyncedTs = 500
      await appState.updateBalances(const Balances(rev: 1));

      fake.remoteData = _dataAt(
          appState.data.lastModified + 1); // someone else pushed meanwhile

      await appState.pushIfDirty();

      expect(fake.pushCount, 0);
    });

    test('pushes once it has synced this session and the remote has not moved',
        () async {
      final fake = _FakeGistSync()..remoteData = _dataAt(500);
      final appState = AppState(storage: _NoopStorage(), gistSync: fake);
      await appState.trySync();
      await appState.updateBalances(const Balances(rev: 1));
      // fake.remoteData is still @500, unchanged since our last known sync.

      await appState.pushIfDirty();

      expect(fake.pushCount, 1);
    });
  });

  group('_lastSyncedTs survives an app restart', () {
    test(
        'an offline edit made after a confirmed sync still pushes cleanly '
        'after the app is relaunched', () async {
      final lastSyncedTsBox = <int?>[null];
      final dataBox = <AppData?>[null];

      final fake1 = _FakeGistSync()..remoteData = _dataAt(500);
      final appState1 = AppState(
        storage:
            _NoopStorage(lastSyncedTsBox: lastSyncedTsBox, dataBox: dataBox),
        gistSync: fake1,
      );
      await appState1.trySync(); // confirmed sync point: local == remote == 500

      await appState1
          .updateBalances(const Balances(rev: 7)); // offline edit, unsynced

      // "Restart": brand-new AppState/GistSyncService, storage backed by
      // the same in-memory boxes — mirrors what SharedPreferences actually
      // does across a real app relaunch. Without persisting
      // `_lastSyncedTs` across that boundary, this used to reset to 0 and
      // make the untouched remote (500) look like it had moved since the
      // last known sync point, popping a conflict dialog for no reason.
      final fake2 = _FakeGistSync()..remoteData = _dataAt(500);
      final appState2 = AppState(
        storage:
            _NoopStorage(lastSyncedTsBox: lastSyncedTsBox, dataBox: dataBox),
        gistSync: fake2,
      );
      await appState2.init();

      expect(appState2.pendingConflict, isNull);
      expect(fake2.pushCount, 1); // the offline edit gets pushed, not blocked
    });
  });
}
