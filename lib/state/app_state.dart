import 'package:flutter/foundation.dart';

import '../data/gist_sync_service.dart';
import '../data/storage_service.dart';
import '../models/app_data.dart';
import '../models/goal.dart';
import '../models/transaction.dart';
import '../utils/formatters.dart';

enum SyncStatus { idle, syncing, error }

/// Central app state: owns the [AppData] blob, all mutations, local
/// persistence, and Gist sync. Every mutation bumps `_lastModified` so the
/// "newest wins" sync rule has something to compare.
class AppState extends ChangeNotifier {
  final StorageService _storage = StorageService();
  final GistSyncService gistSync = GistSyncService();

  AppData _data = AppData.empty();
  AppData get data => _data;

  // Seeded synchronously (not just in `init()`) so the very first frame —
  // before local storage/Gist have loaded — always has a valid month rather
  // than an empty string, which would crash any `monthLabel()` call.
  late String selectedMonth =
      _data.months.isNotEmpty ? _data.months.last : todayIso().substring(0, 7);
  SyncStatus syncStatus = SyncStatus.idle;
  String? syncError;
  int _lastSyncedTs = 0;

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

  Future<void> trySync() async {
    if (!await gistSync.hasCredentials()) return;
    syncStatus = SyncStatus.syncing;
    notifyListeners();
    try {
      final outcome = await gistSync.sync(_data);
      if (outcome.adoptedRemote) {
        _data = outcome.data;
        await _storage.save(_data);
        _ensureSelectedMonthValid();
      }
      _lastSyncedTs = _data.lastModified;
      syncError = null;
      syncStatus = SyncStatus.idle;
    } catch (e) {
      syncError = e.toString();
      syncStatus = SyncStatus.error;
    }
    notifyListeners();
  }

  /// Push-only sync, meant for app lifecycle (background/close) hooks: does
  /// nothing if the remote is already at least as new.
  Future<void> pushIfDirty() async {
    if (!await gistSync.hasCredentials()) return;
    try {
      final pushed = await gistSync.pushIfNewer(_data, _lastSyncedTs);
      if (pushed) _lastSyncedTs = _data.lastModified;
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
    _data = _data.copyWith(txns: [..._data.txns, t]);
    _touch();
    await _persist();
  }

  Future<void> updateTxn(Txn t) async {
    _data = _data.copyWith(
        txns: _data.txns.map((e) => e.id == t.id ? t : e).toList());
    _touch();
    await _persist();
  }

  Future<void> deleteTxn(int id) async {
    _data = _data.copyWith(txns: _data.txns.where((e) => e.id != id).toList());
    _touch();
    await _persist();
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
      selectMonth(next);
      return;
    }
    final months = [..._data.months, next];
    final budgets = Map<String, Map<String, double>>.from(_data.budgets);
    budgets[next] = Map<String, double>.from(_data.budgets[last] ?? {});
    _data = _data.copyWith(months: months, budgets: budgets);
    _touch();
    await _persist();
    selectMonth(next);
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
    await updateTxn(txn.copyWith(cleared: !txn.cleared));
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
    var txns = _data.txns.map((t) {
      if (t.acct == acct && t.cleared && !t.locked) {
        return t.copyWith(cleared: false, locked: true);
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
        ),
      ];
    }

    _data = _data.copyWith(txns: txns);
    _touch();
    await _persist();
  }

  void selectMonth(String month) {
    selectedMonth = month;
    notifyListeners();
  }
}
