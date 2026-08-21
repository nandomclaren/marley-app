import '../data/categories.dart';
import '../models/app_data.dart';
import 'formatters.dart';

/// Pure functions implementing Marley's financial logic. Ported 1:1 from the
/// web app (`index.html`) — do not "simplify" the math without re-checking
/// against the original.
class Calculations {
  Calculations._();

  /// Sum of the three account opening balances.
  static double totalOpeningBalance(AppData data) {
    return data.balances.rev + data.balances.wise + data.balances.swile;
  }

  /// Total balance across all accounts as of [asOfDate] (inclusive),
  /// excluding 'opening' rows (which are already baked into `balances`).
  static double balanceAsOf(AppData data, String asOfDate) {
    var total = totalOpeningBalance(data);
    for (final t in data.txns) {
      if (t.style == 'opening') continue;
      if (t.date.compareTo(asOfDate) <= 0) {
        total += t.net;
      }
    }
    return total;
  }

  static double saldoHoje(AppData data) => balanceAsOf(data, todayIso());

  /// NDMP: delta between today's balance and the balance on the same
  /// calendar day one month ago.
  static double ndmp(AppData data, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final lastMonthDate = _sameDayLastMonth(today);
    final saldoHojeVal = balanceAsOf(data, toIso(today));
    final saldoLmVal = balanceAsOf(data, toIso(lastMonthDate));
    return saldoHojeVal - saldoLmVal;
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

  /// Cash inflow for [month], across all accounts (used by the Reflect tab's
  /// Income vs Spending chart — distinct from per-category budget "Gasto").
  static double totalIncome(AppData data, String month) {
    return data.txns
        .where((t) => monthOf(t.date) == month && t.style != 'opening')
        .fold(0.0, (a, t) => a + t.in_);
  }

  static double totalOutflow(AppData data, String month) {
    return data.txns
        .where((t) => monthOf(t.date) == month && t.style != 'opening')
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
