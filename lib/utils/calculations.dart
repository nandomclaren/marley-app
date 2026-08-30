import '../data/categories.dart';
import '../models/app_data.dart';
import '../models/transaction.dart';
import 'formatters.dart';

/// Pure functions implementing Marley's financial logic. Ported 1:1 from the
/// web app (`index.html`) — do not "simplify" the math without re-checking
/// against the original.
class Calculations {
  Calculations._();

  /// Sum of the three account opening balances (the manually-set starting
  /// point, i.e. `data.balances` — matches the web app's `getOp()`/`total`).
  static double totalOpeningBalance(AppData data) {
    return data.balances.rev + data.balances.wise + data.balances.swile;
  }

  /// Running per-account + total balance after each transaction, walked in
  /// (date, id) order from `data.balances`. Mirrors the web app's
  /// `compute()` *exactly*: it does NOT skip 'opening'-styled rows — every
  /// transaction affects the running total regardless of style. `style`
  /// only ever excludes a row from *selecting a reference point* below
  /// (see [fluxoSummary]), never from the running sum itself.
  static List<LedgerRow> computeRows(AppData data) {
    final sorted = [...data.txns]..sort((a, b) {
        final c = a.date.compareTo(b.date);
        if (c != 0) return c;
        return a.id.compareTo(b.id);
      });
    var rev = data.balances.rev;
    var wise = data.balances.wise;
    var swile = data.balances.swile;
    final rows = <LedgerRow>[];
    for (final t in sorted) {
      switch (t.acct) {
        case 'Revolut':
          rev += t.net;
          break;
        case 'Wise':
          wise += t.net;
          break;
        case 'Swile':
          swile += t.net;
          break;
      }
      rows.add(LedgerRow(txn: t, bRev: rev, bWise: wise, bSwile: swile));
    }
    return rows;
  }

  /// The four Fluxo header cards for [month] ('YYYY-MM'), ported 1:1 from
  /// the web app's `render()`: start-of-month balance, today's balance,
  /// projected end-of-month balance, and the lowest point reached during
  /// the month (with the date it happened).
  static FluxoSummary fluxoSummary(AppData data, String month,
      {DateTime? now}) {
    final rows = computeRows(data);
    final total = totalOpeningBalance(data);
    final today = toIso(now ?? DateTime.now());
    final monthStart = '$month-01';
    final monthEnd = lastDayOfMonth(month);

    final priorRows = rows
        .where((r) =>
            r.txn.date.compareTo(monthStart) < 0 && r.txn.style != 'opening')
        .toList();
    final startBal = priorRows.isNotEmpty ? priorRows.last.bTot : total;

    final monthRows = rows
        .where((r) =>
            r.txn.date.compareTo(monthStart) >= 0 &&
            r.txn.date.compareTo(monthEnd) <= 0)
        .toList();
    final finalVal = monthRows.isNotEmpty ? monthRows.last.bTot : startBal;

    final todayRows =
        rows.where((r) => r.txn.date.compareTo(today) <= 0).toList();
    final hojeVal = todayRows.isNotEmpty ? todayRows.last.bTot : startBal;

    double? minVal;
    String? minDate;
    if (monthRows.isNotEmpty) {
      minVal = monthRows.map((r) => r.bTot).reduce((a, b) => a < b ? a : b);
      minDate = monthRows.firstWhere((r) => r.bTot == minVal).txn.date;
    }

    return FluxoSummary(
      startBal: startBal,
      hojeVal: hojeVal,
      finalVal: finalVal,
      minVal: minVal,
      minDate: minDate,
    );
  }

  static double saldoHoje(AppData data, {DateTime? now}) {
    final today = now ?? DateTime.now();
    return fluxoSummary(data, monthOf(toIso(today)), now: today).hojeVal;
  }

  /// NDMP: delta between today's balance and the balance on the same
  /// calendar day one month ago. Ported from the web app's NDMP row logic —
  /// note the last-month reference deliberately falls back to 0 (not the
  /// start-of-month balance) when there's no transaction on/before that
  /// date, matching the original's quirk exactly.
  static double ndmp(AppData data, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final currentMonth = monthOf(toIso(today));
    final hojeVal = fluxoSummary(data, currentMonth, now: today).hojeVal;

    final lastMonthDate = _sameDayLastMonth(today);
    final lmIso = toIso(lastMonthDate);
    final rows = computeRows(data);
    final lmRows = rows.where((r) => r.txn.date.compareTo(lmIso) <= 0).toList();
    final lmBal = lmRows.isNotEmpty ? lmRows.last.bTot : 0.0;

    return hojeVal - lmBal;
  }

  static DateTime _sameDayLastMonth(DateTime d) {
    var year = d.year;
    var month = d.month - 1;
    if (month < 1) {
      month = 12;
      year--;
    }
    final daysInTargetMonth = DateTime(year, month + 1, 0).day;
    final day = d.day > daysInTargetMonth ? daysInTargetMonth : d.day;
    return DateTime(year, month, day);
  }

  // ---------------------------------------------------------------------
  // Budget / carryover
  // ---------------------------------------------------------------------

  /// Amount spent in [cat] during [month] ('YYYY-MM'): outflows net of any
  /// inflows (refunds) tagged with that category in that month.
  static double spentForCategory(AppData data, String month, String cat) {
    var spent = 0.0;
    for (final t in data.txns) {
      if (t.cat != cat) continue;
      if (monthOf(t.date) != month) continue;
      spent += t.out - t.in_;
    }
    return spent;
  }

  static const String _carryStartFloor = '2026-02';

  /// Carryover balance available to [cat] going *into* [month], i.e. before
  /// that month's own budget/spend is applied.
  ///
  /// Recursively: `carry[m] = carry[m-1] + budget[m-1][cat] - spent[m-1][cat]`.
  /// The first eligible month (the earliest budgeted month after February,
  /// which is excluded as an incomplete startup month) starts with carry 0.
  static Map<String, double> carryoverSeries(AppData data, String cat) {
    final eligibleMonths = data.months
        .where((m) =>
            m.compareTo(_carryStartFloor) > 0 && data.budgets.containsKey(m))
        .toList()
      ..sort();

    final carry = <String, double>{};
    for (var i = 0; i < eligibleMonths.length; i++) {
      final m = eligibleMonths[i];
      if (i == 0) {
        carry[m] = 0;
      } else {
        final prev = eligibleMonths[i - 1];
        final prevBudget = data.budgets[prev]?[cat] ?? 0;
        final prevSpent = spentForCategory(data, prev, cat);
        carry[m] = (carry[prev] ?? 0) + prevBudget - prevSpent;
      }
    }
    return carry;
  }

  static double carryoverFor(AppData data, String cat, String month) {
    return carryoverSeries(data, cat)[month] ?? 0;
  }

  /// Available = carry-in + this month's budget - this month's spend.
  static double availableFor(AppData data, String cat, String month) {
    final carry = carryoverFor(data, cat, month);
    final budget = data.budgets[month]?[cat] ?? 0;
    final spent = spentForCategory(data, month, cat);
    return carry + budget - spent;
  }

  static double totalBudgeted(AppData data, String month) {
    final cats = data.budgets[month] ?? {};
    return cats.values.fold(0.0, (a, b) => a + b);
  }

  static double totalSpent(AppData data, String month) {
    return kAllCategories.fold(
        0.0, (a, cat) => a + spentForCategory(data, month, cat));
  }

  static double totalAvailable(AppData data, String month) {
    return kAllCategories.fold(
        0.0, (a, cat) => a + availableFor(data, cat, month));
  }

  static const String _globalFloorDate = '2026-02-28';
  static const String _globalFloorMonth = '2026-02';

  /// Budget tab's "A Alocar" header card: total income actually received
  /// (post-startup, up to today) minus everything ever allocated to a
  /// budget category across every month — a global running total, not
  /// scoped to the selected month. Matches the web app's `aAlocar`.
  static double toBeBudgeted(AppData data, {String? asOf}) {
    final cutoff = asOf ?? todayIso();
    final allReceivedIncome = data.txns
        .where((t) =>
            t.date.compareTo(_globalFloorDate) > 0 &&
            t.in_ > 0 &&
            t.style != 'opening' &&
            t.date.compareTo(cutoff) <= 0)
        .fold(0.0, (a, t) => a + t.in_);

    var allAllocations = 0.0;
    data.budgets.forEach((month, cats) {
      if (month.compareTo(_globalFloorMonth) <= 0) return;
      allAllocations += cats.values.fold(0.0, (a, b) => a + b);
    });

    return allReceivedIncome - allAllocations;
  }

  /// Web's `autoGenerateRecurring()`: when the user switches to [month],
  /// copy forward any recurring/fixed/salary/critical transaction from the
  /// *previous* month, shifting its date one month ahead (day clamped to
  /// the new month's last day). Skips a description already present in
  /// [month], and any description explicitly removed from it via
  /// `data.skipRecurring`. Returns only the new rows to add — callers are
  /// responsible for persisting them.
  static List<Txn> autoGenerateRecurringTxns(AppData data, String month) {
    final parts = month.split('-');
    final cy = int.parse(parts[0]);
    final cmo = int.parse(parts[1]);
    final prevMo = cmo == 1 ? 12 : cmo - 1;
    final prevY = cmo == 1 ? cy - 1 : cy;
    final prevMonth = '$prevY-${prevMo.toString().padLeft(2, '0')}';

    final recFromPrev = data.txns.where((t) =>
        t.date.startsWith(prevMonth) &&
        (t.recurring ||
            t.style == 'fixed' ||
            t.style == 'salary' ||
            t.style == 'critical') &&
        t.style != 'opening');

    final skip = data.skipRecurring[month] ?? const [];
    var nextId = data.txns.isEmpty
        ? 1
        : data.txns.map((t) => t.id).reduce((a, b) => a > b ? a : b) + 1;

    final generated = <Txn>[];
    for (final t in recFromPrev) {
      if (data.txns.any((x) => x.date.startsWith(month) && x.desc == t.desc)) {
        continue;
      }
      if (skip.contains(t.desc)) continue;

      final dParts = t.date.split('-');
      final y = int.parse(dParts[0]);
      final mo = int.parse(dParts[1]);
      final d = int.parse(dParts[2]);
      final nextMo = mo == 12 ? 1 : mo + 1;
      final nextY = mo == 12 ? y + 1 : y;
      final lastDay = DateTime(nextY, nextMo + 1, 0).day;
      final day = d < lastDay ? d : lastDay;
      final nextDate =
          '$nextY-${nextMo.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
      final nextDateMonth = nextDate.substring(0, 7);
      if (!data.months.contains(nextDateMonth)) continue;

      generated.add(t.copyWith(
        id: nextId++,
        date: nextDate,
        cleared: false,
        locked: false,
      ));
    }
    return generated;
  }

  /// Spending for [cat] in [month] as shown by the Reflect tab's Spending
  /// Breakdown — distinct from Budget's `spentForCategory`: this one uses
  /// raw outflow (not net of refunds), excludes 'opening' rows, and only
  /// counts up to [asOf] (today), matching the web app's chart filter.
  static double reflectSpentForCategory(AppData data, String month, String cat,
      {String? asOf}) {
    final cutoff = asOf ?? todayIso();
    return data.txns
        .where((t) =>
            t.cat == cat &&
            monthOf(t.date) == month &&
            t.date.compareTo(cutoff) <= 0 &&
            t.style != 'opening' &&
            t.out > 0)
        .fold(0.0, (a, t) => a + t.out);
  }

  /// Cash inflow for [month], across accounts (used by the Reflect tab's
  /// Income vs Spending chart — distinct from per-category budget "Gasto").
  /// Only counts up to [asOf] (today) and excludes account-less rows, per
  /// the web app's `incData` filter.
  static double totalIncome(AppData data, String month, {String? asOf}) {
    final cutoff = asOf ?? todayIso();
    return data.txns
        .where((t) =>
            monthOf(t.date) == month &&
            t.in_ > 0 &&
            t.style != 'opening' &&
            t.date.compareTo(cutoff) <= 0 &&
            t.acct != kNoAccount)
        .fold(0.0, (a, t) => a + t.in_);
  }

  static double totalOutflow(AppData data, String month, {String? asOf}) {
    final cutoff = asOf ?? todayIso();
    return data.txns
        .where((t) =>
            monthOf(t.date) == month &&
            t.out > 0 &&
            t.style != 'opening' &&
            t.date.compareTo(cutoff) <= 0)
        .fold(0.0, (a, t) => a + t.out);
  }

  // ---------------------------------------------------------------------
  // Net worth
  // ---------------------------------------------------------------------

  static ({
    double rev,
    double wise,
    double swile,
    double assets,
    double debts,
    double netWorth
  }) netWorthAsOf(AppData data, String asOfDate) {
    var rev = data.balances.rev;
    var wise = data.balances.wise;
    var swile = data.balances.swile;

    for (final t in data.txns) {
      if (t.date.compareTo(asOfDate) > 0) continue;
      switch (t.acct) {
        case 'Revolut':
          rev += t.net;
          break;
        case 'Wise':
          wise += t.net;
          break;
        case 'Swile':
          swile += t.net;
          break;
      }
    }

    double posSum(List<double> vs) =>
        vs.where((v) => v > 0).fold(0.0, (a, b) => a + b);
    double negSum(List<double> vs) =>
        vs.where((v) => v < 0).fold(0.0, (a, b) => a + b.abs());

    final assets = posSum([rev, wise, swile]);
    final debts = negSum([rev, wise, swile]);
    return (
      rev: rev,
      wise: wise,
      swile: swile,
      assets: assets,
      debts: debts,
      netWorth: assets - debts
    );
  }

  static double netWorthForMonth(AppData data, String yyyymm) {
    return netWorthAsOf(data, lastDayOfMonth(yyyymm)).netWorth;
  }

  // ---------------------------------------------------------------------
  // Accounts / reconcile
  // ---------------------------------------------------------------------

  static double openingBalanceForAccount(Balances b, String acct) {
    switch (acct) {
      case 'Revolut':
        return b.rev;
      case 'Wise':
        return b.wise;
      case 'Swile':
        return b.swile;
      default:
        return 0;
    }
  }

  /// The "cleared balance" shown at the start of a reconcile flow: opening
  /// balance for [acct] plus every cleared-or-locked transaction on it up
  /// to [asOf] (today), excluding 'opening' rows. Matches the web app's
  /// `openRecModal()` exactly.
  static double clearedBalanceForAccount(AppData data, String acct,
      {String? asOf}) {
    final cutoff = asOf ?? todayIso();
    final start = openingBalanceForAccount(data.balances, acct);
    final sum = data.txns
        .where((t) =>
            t.acct == acct &&
            t.style != 'opening' &&
            (t.cleared || t.locked) &&
            t.date.compareTo(cutoff) <= 0)
        .fold(0.0, (a, t) => a + t.net);
    return start + sum;
  }

  // ---------------------------------------------------------------------
  // Age of Money (FIFO)
  // ---------------------------------------------------------------------

  /// Returns the Age of Money in days as of [asOfDate], or null if outflows
  /// exceed all known inflows (queue exhausted).
  static int? ageOfMoney(AppData data, String asOfDate) {
    final eligibleTxns =
        data.txns.where((t) => t.date.compareTo(asOfDate) <= 0).toList();
    if (eligibleTxns.isEmpty && totalOpeningBalance(data) <= 0) return null;

    final buckets = <_MoneyBucket>[];

    final initBal = totalOpeningBalance(data);
    if (initBal > 0) {
      String firstDate = asOfDate;
      if (data.txns.isNotEmpty) {
        final sorted = [...data.txns]..sort((a, b) => a.date.compareTo(b.date));
        firstDate = sorted.first.date;
      }
      buckets.add(_MoneyBucket(firstDate, initBal));
    }

    final inflows = eligibleTxns
        .where((t) => t.in_ > 0 && t.style != 'opening')
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    for (final t in inflows) {
      buckets.add(_MoneyBucket(t.date, t.in_));
    }

    if (buckets.isEmpty) return null;

    final outflows = eligibleTxns
        .where((t) => t.out > 0 && t.style != 'opening')
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    const epsilon = 0.005;
    for (final t in outflows) {
      var remaining = t.out;
      while (remaining > epsilon) {
        if (buckets.isEmpty) return null;
        final front = buckets.first;
        if (front.amount <= remaining + epsilon) {
          remaining -= front.amount;
          buckets.removeAt(0);
        } else {
          front.amount -= remaining;
          remaining = 0;
        }
      }
    }

    if (buckets.isEmpty) return null;

    final oldestBucketDate = parseIso(buckets.first.date);
    final asOf = parseIso(asOfDate);
    return asOf.difference(oldestBucketDate).inDays;
  }
}

class _MoneyBucket {
  final String date;
  double amount;
  _MoneyBucket(this.date, this.amount);
}

/// One row of [Calculations.computeRows]: a transaction plus the running
/// per-account balances immediately after it.
class LedgerRow {
  final Txn txn;
  final double bRev;
  final double bWise;
  final double bSwile;
  double get bTot => bRev + bWise + bSwile;

  LedgerRow(
      {required this.txn,
      required this.bRev,
      required this.bWise,
      required this.bSwile});
}

/// The four Fluxo header cards for a given month.
class FluxoSummary {
  final double startBal;
  final double hojeVal;
  final double finalVal;
  final double? minVal;
  final String? minDate;

  const FluxoSummary({
    required this.startBal,
    required this.hojeVal,
    required this.finalVal,
    this.minVal,
    this.minDate,
  });
}
