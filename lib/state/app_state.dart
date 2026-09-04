import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/gist_sync_service.dart';
import '../data/storage_service.dart';
import '../models/app_data.dart';
import '../models/goal.dart';
import '../models/transaction.dart';
import '../utils/calculations.dart';
import '../utils/formatters.dart';

enum SyncStatus { idle, syncing, error }

/// A snapshot of the two divergent copies of the data, presented to the
/// user so *they* pick a winner instead of the app silently guessing.
class SyncConflict {
  final AppData remote;
  final AppData local;
  const SyncConflict({required this.remote, required this.local});
}

/// Central app state: owns the [AppData] blob, all mutations, local
/// persistence, and Gist sync. Every mutation bumps `_lastModified` so the
/// "newest wins" sync rule has something to compare.
class AppState extends ChangeNotifier {
  final StorageService _storage;
  final GistSyncService gistSync;

  AppState({StorageService? storage, GistSyncService? gistSync})
      : _storage = storage ?? StorageService(),
        gistSync = gistSync ?? GistSyncService();

  AppData _data = AppData.empty();
  AppData get data => _data;

  // Seeded synchronously (not just in `init()`) so the very first frame —
  // before local storage/Gist have loaded — always has a valid month rather
  // than an empty string, which would crash any `monthLabel()` call.
  late String selectedMonth =
      _data.months.isNotEmpty ? _data.months.last : todayIso().substring(0, 7);
  SyncStatus syncStatus = SyncStatus.idle;
  String? syncError;

  // The remote's `_lastModified` as of the last time this *device* actually
  // looked at it (pull or push) — NOT the same as `_data.lastModified`,
  // which only reflects our own edits. Comparing against this (rather than
  // just "is local newer than remote") is what lets us tell "remote hasn't
  // moved, safe to push" apart from "remote moved since we last looked,
  // ask before overwriting" even when local also looks newer by raw
  // timestamp. Mirrors the same fix applied on the web app after a stale
  // local timestamp caused it to silently overwrite a week of Flutter-app
  // data with older web data.
  //
  // Persisted (via StorageService.saveLastSyncedTs), not just held in
  // memory: it has to survive an app restart. It used to live in memory
  // only, which meant it reset to 0 on every cold start — so the very
  // first sync of each new session almost always saw `remote > 0 (the
  // reset value)` and treated that as "remote moved since we last looked",
  // popping the conflict dialog even when remote and local were byte
  // identical. Seeded from storage in `init()`; use `_setLastSyncedTs` to
  // change it so every update stays persisted too.
  int _lastSyncedTs = 0;

  // Never push from a background/lifecycle hook before this session has
  // actually verified the remote at least once — pushing based on a
  // timestamp alone, without ever having looked at what's actually on the
  // server this session, is exactly how that overwrite happened.
  bool _hasSyncedThisSession = false;

  // Every transaction CRUD (add/edit/delete/clear/reconcile) now kicks off
  // a sync right away instead of waiting for a manual tap or the app being
  // backgrounded. Those actions can fire in quick succession (e.g. clearing
  // several rows), so guard against overlapping network calls: a `trySync`
  // that starts while one is already running just marks that another pass
  // is needed once the current one finishes, rather than racing it.
  bool _syncInFlight = false;
  bool _syncQueuedAgain = false;

  /// Set when a real conflict is detected: the remote moved since our last
  /// known sync point *and* local also looks newer. Non-null means a
  /// dialog should be shown asking the user to pick a side — see
  /// [resolveConflictKeepLocal] / [resolveConflictUseRemote].
  SyncConflict? pendingConflict;

  bool? _manualDarkOverride;
  bool get isDarkModeOverridden => _manualDarkOverride != null;
  bool get isDarkMode => _manualDarkOverride ?? isNightHourNow();

  static bool isNightHourNow() {
    final h = DateTime.now().hour;
    return h >= 18 || h < 6;
  }

  void setManualDarkOverride(bool? value) {
    _manualDarkOverride = value;
    notifyListeners();
  }

  bool _initialized = false;
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final loaded = await _storage.load();
      if (loaded != null) {
        _data = loaded;
      }
    } catch (_) {
      // Best-effort; fall back to the in-memory default and let sync
      // (below) recover from the Gist if local storage is unavailable.
    }
    try {
      _lastSyncedTs = await _storage.loadLastSyncedTs() ?? 0;
    } catch (_) {
      _lastSyncedTs = 0;
    }
    _pickInitialMonth();
    notifyListeners();
    await trySync();
  }

  void _pickInitialMonth() {
    if (_data.months.isEmpty) {
      selectedMonth = todayIso().substring(0, 7);
      return;
    }
    final currentReal = todayIso().substring(0, 7);
    selectedMonth =
        _data.months.contains(currentReal) ? currentReal : _data.months.last;
  }

  void _ensureSelectedMonthValid() {
    if (!_data.months.contains(selectedMonth)) {
      selectedMonth = _data.months.isNotEmpty ? _data.months.last : '';
    }
  }

  // ---------------------------------------------------------------------
  // Sync
  // ---------------------------------------------------------------------

  /// Updates [_lastSyncedTs] and persists it right away — it has to survive
  /// an app restart (see the field doc), not just this session, or every
  /// cold start would look exactly like a genuine conflict the moment the
  /// remote timestamp is nonzero, even when nothing actually diverged.
  Future<void> _setLastSyncedTs(int ts) async {
    _lastSyncedTs = ts;
    try {
      await _storage.saveLastSyncedTs(ts);
    } catch (_) {
      // Best-effort; worst case a future cold start re-shows one conflict
      // dialog it could have avoided.
    }
  }

  /// Manual sync (button, and once on app start): always fetches the
  /// remote first, then decides:
  ///  - no remote yet, or remote unchanged since our last known sync point
  ///    → safe to push local.
  ///  - remote is newer than local → safe to adopt remote outright (that
  ///    direction never destroys anything of ours).
  ///  - remote moved since we last looked AND local also looks newer →
  ///    genuine conflict, do not guess: surface [pendingConflict] and stop.
  Future<void> trySync() async {
    if (_syncInFlight) {
      _syncQueuedAgain = true;
      return;
    }
    _syncInFlight = true;
    try {
      bool hasCreds;
      try {
        hasCreds = await gistSync.hasCredentials();
      } catch (_) {
        // Reading credentials shouldn't be able to fail in practice (it's
        // just secure-storage reads), but this now runs automatically after
        // every transaction edit rather than only from an explicit user
        // tap — so treat any failure here the same as "not configured yet"
        // instead of surfacing an error for something the user didn't ask
        // for.
        return;
      }
      if (!hasCreds) return;
      syncStatus = SyncStatus.syncing;
      notifyListeners();
      try {
        final remote = await gistSync.fetchRemote();
        _hasSyncedThisSession = true;

        if (remote == null) {
          await gistSync.pushData(_data);
          await _setLastSyncedTs(_data.lastModified);
        } else if (remote.lastModified > _data.lastModified) {
          _data = remote;
          await _storage.save(_data);
          _ensureSelectedMonthValid();
          await _setLastSyncedTs(remote.lastModified);
        } else if (remote.lastModified == _data.lastModified) {
          // Byte-identical states (most cold starts, once this device has
          // synced before): nothing to reconcile or push.
          await _setLastSyncedTs(remote.lastModified);
        } else if (remote.lastModified > _lastSyncedTs) {
          pendingConflict = SyncConflict(remote: remote, local: _data);
        } else {
          await gistSync.pushData(_data);
          await _setLastSyncedTs(_data.lastModified);
        }
        syncError = null;
        syncStatus = SyncStatus.idle;
      } catch (e) {
        syncError = e.toString();
        syncStatus = SyncStatus.error;
      }
      notifyListeners();
    } finally {
      _syncInFlight = false;
      if (_syncQueuedAgain) {
        _syncQueuedAgain = false;
        unawaited(trySync());
      }
    }
  }

  /// Fire-and-forget sync kicked off right after a transaction CRUD
  /// mutation (add/edit/delete/clear/reconcile), so changes reach the Gist
  /// without waiting for a manual tap or the app being backgrounded.
  /// Deliberately not awaited by callers — network shouldn't block the UI
  /// from closing a sheet or reflecting the edit immediately; `trySync`
  /// still surfaces the usual conflict dialog / error state on its own.
  void _autoSyncTxns() {
    unawaited(trySync());
  }

  /// User picked "keep this device's data" on a conflict: push local,
  /// overwriting the server.
  Future<void> resolveConflictKeepLocal() async {
    if (pendingConflict == null) return;
    pendingConflict = null;
    try {
      await gistSync.pushData(_data);
      await _setLastSyncedTs(_data.lastModified);
      syncError = null;
      syncStatus = SyncStatus.idle;
    } catch (e) {
      syncError = e.toString();
      syncStatus = SyncStatus.error;
    }
    notifyListeners();
  }

  /// User picked "use the server's data" on a conflict: adopt remote,
  /// discarding local's unsynced changes.
  Future<void> resolveConflictUseRemote() async {
    final remote = pendingConflict?.remote;
    pendingConflict = null;
    if (remote == null) return;
    _data = remote;
    await _storage.save(_data);
    _ensureSelectedMonthValid();
    await _setLastSyncedTs(remote.lastModified);
    notifyListeners();
  }

  /// Push-only sync, meant for app lifecycle (background/close) hooks.
  /// Refuses to push if this session never verified the remote (nothing to
  /// safely compare against), and re-checks the remote's current
  /// timestamp right before pushing — if someone else pushed since our
  /// last known sync point, backs off silently rather than risk a
  /// clobber with no UI available to ask.
  Future<void> pushIfDirty() async {
    if (!_hasSyncedThisSession) return;
    if (!await gistSync.hasCredentials()) return;
    if (_data.lastModified <= _lastSyncedTs) return;
    try {
      final remoteTs = await gistSync.fetchRemoteLastModified();
      if (remoteTs != null && remoteTs > _lastSyncedTs) {
        return; // someone else moved the remote; let a manual sync sort it out
      }
      await gistSync.pushData(_data);
      await _setLastSyncedTs(_data.lastModified);
    } catch (_) {
      // Best-effort; the next manual sync will surface any real problem.
    }
  }

  // ---------------------------------------------------------------------
  // Mutations
  // ---------------------------------------------------------------------

  void _touch() {
    _data = _data.copyWith(lastModified: DateTime.now().millisecondsSinceEpoch);
  }

  /// Notifies listeners immediately (so the UI reflects the mutation
  /// without waiting on disk I/O), then persists in the background. A
  /// storage failure here shouldn't roll back the in-memory state or block
  /// the UI — the next successful save/sync will catch up.
  Future<void> _persist() async {
    notifyListeners();
    try {
      await _storage.save(_data);
    } catch (_) {
      // Best-effort; local persistence failures aren't fatal to a session.
    }
  }

  int nextTxnId() {
    if (_data.txns.isEmpty) return 1;
    return _data.txns.map((t) => t.id).reduce((a, b) => a > b ? a : b) + 1;
  }

  Future<void> addTxn(Txn t) async {
    // Went through this method == the user typed it in via "+" — forced
    // here rather than trusting the caller, so it's never possible to add
    // a txn that doesn't count as manually-added.
    _data = _data.copyWith(
        txns: [..._data.txns, t.copyWith(addedManually: true)]);
    _touch();
    await _persist();
    _autoSyncTxns();
  }

  Future<void> updateTxn(Txn t) async {
    _data = _data.copyWith(
        txns: _data.txns.map((e) => e.id == t.id ? t : e).toList());
    _touch();
    await _persist();
    _autoSyncTxns();
  }

  Future<void> deleteTxn(int id) async {
    Txn? txn;
    for (final t in _data.txns) {
      if (t.id == id) {
        txn = t;
        break;
      }
    }
    // Deleting a recurring/fixed/salary/critical row means "not this
    // month" — remember that so `autoGenerateRecurringTxns` doesn't bring
    // it right back next time this month is opened. Matches the web app's
    // `delTxnFromModal`.
    var skipRecurring = _data.skipRecurring;
    if (txn != null &&
        (txn.recurring ||
            ['fixed', 'salary', 'critical'].contains(txn.style)) &&
        txn.style != 'opening') {
      final month = monthOf(txn.date);
      final monthSkips = <String>[
        ...(skipRecurring[month] ?? const <String>[])
      ];
      if (!monthSkips.contains(txn.desc)) monthSkips.add(txn.desc);
      skipRecurring = {...skipRecurring, month: monthSkips};
    }

    _data = _data.copyWith(
      txns: _data.txns.where((e) => e.id != id).toList(),
      skipRecurring: skipRecurring,
    );
    _touch();
    await _persist();
    _autoSyncTxns();
  }

  Future<void> setBudget(String month, String cat, double amount) async {
    final monthBudgets = Map<String, double>.from(_data.budgets[month] ?? {});
    monthBudgets[cat] = amount;
    final budgets = Map<String, Map<String, double>>.from(_data.budgets);
    budgets[month] = monthBudgets;
    _data = _data.copyWith(budgets: budgets);
    _touch();
    await _persist();
  }

  Future<void> moveMoney({
    required String month,
    required String fromCat,
    required String toCat,
    required double amount,
  }) async {
    final monthBudgets = Map<String, double>.from(_data.budgets[month] ?? {});
    monthBudgets[fromCat] = (monthBudgets[fromCat] ?? 0) - amount;
    monthBudgets[toCat] = (monthBudgets[toCat] ?? 0) + amount;
    final budgets = Map<String, Map<String, double>>.from(_data.budgets);
    budgets[month] = monthBudgets;
    _data = _data.copyWith(budgets: budgets);
    _touch();
    await _persist();
  }

  Future<void> setGoal(String cat, Goal goal) async {
    final goals = Map<String, Goal>.from(_data.goals);
    goals[cat] = goal;
    _data = _data.copyWith(goals: goals);
    _touch();
    await _persist();
  }

  Future<void> deleteGoal(String cat) async {
    final goals = Map<String, Goal>.from(_data.goals);
    goals.remove(cat);
    _data = _data.copyWith(goals: goals);
    _touch();
    await _persist();
  }

  Future<void> addNextMonth() async {
    final last = _data.months.isNotEmpty
        ? _data.months.last
        : todayIso().substring(0, 7);
    final next = nextMonth(last);
    if (_data.months.contains(next)) {
      await selectMonth(next);
      return;
    }
    final months = [..._data.months, next];
    final budgets = Map<String, Map<String, double>>.from(_data.budgets);
    budgets[next] = Map<String, double>.from(_data.budgets[last] ?? {});
    _data = _data.copyWith(months: months, budgets: budgets);
    _touch();
    await _persist();
    await selectMonth(next);
  }

  Future<void> updateBalances(Balances b) async {
    _data = _data.copyWith(balances: b);
    _touch();
    await _persist();
  }

  /// Flips `cleared` on a transaction (swipe-to-clear). No-op on locked
  /// (already reconciled) rows — matches the web app's `toggleCleared`.
  Future<void> toggleCleared(int id) async {
    Txn? txn;
    for (final t in _data.txns) {
      if (t.id == id) {
        txn = t;
        break;
      }
    }
    if (txn == null || txn.locked) return;
    final nowCleared = !txn.cleared;
    await updateTxn(nowCleared
        ? txn.copyWith(
            cleared: true,
            settledAt: DateTime.now().millisecondsSinceEpoch)
        : txn.copyWith(cleared: false, clearSettledAt: true));
  }

  /// Reconcile [acct]: locks every cleared-but-unlocked transaction on it,
  /// and — when the user supplied [realBalance] (it didn't match what the
  /// app had) — appends a locked correction transaction for the
  /// difference. Matches the web app's `lockClearedTxns` +
  /// `recSubmitCorrection` (the "yes, it matches" path passes no
  /// [realBalance] and only locks).
  Future<void> reconcileAccount({
    required String acct,
    double? realBalance,
    required double clearedBalanceBefore,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    var txns = _data.txns.map((t) {
      if (t.acct == acct && t.cleared && !t.locked) {
        return t.copyWith(cleared: false, locked: true, settledAt: now);
      }
      return t;
    }).toList();

    if (realBalance != null) {
      final diff = realBalance - clearedBalanceBefore;
      txns = [
        ...txns,
        Txn(
          id: nextTxnId(),
          date: todayIso(),
          desc: '🔧 Transação de correção',
          acct: acct,
          out: diff < 0 ? diff.abs() : 0,
          in_: diff > 0 ? diff : 0,
          notes:
              'Correção de reconciliação (esperado ${formatEur(realBalance)}, '
              'encontrado ${formatEur(clearedBalanceBefore)})',
          cleared: false,
          locked: true,
          settledAt: now,
        ),
      ];
    }

    _data = _data.copyWith(txns: txns);
    _touch();
    await _persist();
    _autoSyncTxns();
  }

  /// Switches the selected month and, like the web app's `setMonth()`,
  /// auto-generates this month's recurring transactions from last month's
  /// (rent, salary, subscriptions, ...) if they aren't already there. A
  /// no-op scan (nothing new to add) just repaints; a scan that actually
  /// adds rows also persists and syncs them.
  Future<void> selectMonth(String month) async {
    selectedMonth = month;
    final generated = Calculations.autoGenerateRecurringTxns(_data, month);
    if (generated.isEmpty) {
      notifyListeners();
      return;
    }
    _data = _data.copyWith(txns: [..._data.txns, ...generated]);
    _touch();
    await _persist();
    _autoSyncTxns();
  }
}
