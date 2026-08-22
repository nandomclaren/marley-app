import 'package:flutter_test/flutter_test.dart';
import 'package:marley/models/app_data.dart';
import 'package:marley/models/transaction.dart';
import 'package:marley/utils/calculations.dart';

AppData _dataWith({
  Balances balances = const Balances(),
  List<Txn> txns = const [],
  Map<String, Map<String, double>> budgets = const {},
}) {
  return AppData(
    lastModified: 0,
    months: budgets.keys.toList()..sort(),
    balances: balances,
    txns: txns,
    budgets: budgets,
    goals: const {},
  );
}

void main() {
  group('computeRows / fluxoSummary', () {
    // Ported from the web app's `compute()`: the running balance walk does
    // NOT skip 'opening'-styled rows — every transaction affects it. Only
    // some *reference-point selections* downstream (e.g. start-of-month)
    // skip opening rows; the cumulative sum itself never does.
    final data = _dataWith(
      balances: const Balances(rev: 100, wise: 50, swile: 10),
      txns: [
        const Txn(
            id: 1,
            date: '2026-01-01',
            desc: 'a',
            acct: 'Revolut',
            out: 0,
            in_: 20,
            style: 'opening'),
        const Txn(
            id: 2,
            date: '2026-01-05',
            desc: 'b',
            acct: 'Revolut',
            out: 30,
            in_: 0),
        const Txn(
            id: 3,
            date: '2026-01-10',
            desc: 'c',
            acct: 'Wise',
            out: 0,
            in_: 15),
        const Txn(
            id: 4,
            date: '2026-02-01',
            desc: 'future',
            acct: 'Wise',
            out: 5,
            in_: 0),
      ],
    );

    test(
        'running balance includes opening-styled rows, unlike per-category spend',
        () {
      final rows = Calculations.computeRows(data);
      expect(rows.map((r) => r.bTot).toList(), [180, 150, 165, 160]);
    });

    test(
        'hojeVal reflects the running balance as of "today", opening rows included',
        () {
      final summary = Calculations.fluxoSummary(data, '2026-01',
          now: DateTime(2026, 1, 15));
      // 100+50+10 (open) +20 (t1, opening) -30 (t2) +15 (t3) = 165; t4 (Feb) excluded.
      expect(summary.hojeVal, 165);
      expect(summary.startBal,
          160); // no prior-month rows -> falls back to total balances
      expect(summary.finalVal, 165); // last row within January
    });
  });

  group('carryoverSeries', () {
    test(
        'starts at 0 for the first eligible month after February, then accumulates',
        () {
      final data = _dataWith(
        budgets: {
          '2026-02': {'A': 999}, // excluded: floor
          '2026-03': {'A': 100},
          '2026-04': {'A': 50},
        },
        txns: [
          const Txn(
              id: 1,
              date: '2026-03-10',
              desc: 'spend',
              acct: 'Revolut',
              out: 40,
              in_: 0,
              cat: 'A'),
        ],
      );
      final carry = Calculations.carryoverSeries(data, 'A');
      expect(carry['2026-03'], 0);
      // carry[04] = carry[03] + budget[03] - spent[03] = 0 + 100 - 40 = 60
      expect(carry['2026-04'], 60);
      expect(Calculations.availableFor(data, 'A', '2026-04'), 60 + 50 - 0);
    });
  });

  group('ageOfMoney (FIFO)', () {
    test('returns null when outflows exceed all known inflows', () {
      final data = _dataWith(
        txns: [
          const Txn(
              id: 1,
              date: '2026-01-01',
              desc: 'in',
              acct: 'Revolut',
              out: 0,
              in_: 10),
          const Txn(
              id: 2,
              date: '2026-01-05',
              desc: 'out',
              acct: 'Revolut',
              out: 50,
              in_: 0),
        ],
      );
      expect(Calculations.ageOfMoney(data, '2026-01-10'), isNull);
    });

    test('ages from the oldest unspent inflow bucket', () {
      final data = _dataWith(
        txns: [
          const Txn(
              id: 1,
              date: '2026-01-01',
              desc: 'in1',
              acct: 'Revolut',
              out: 0,
              in_: 100),
          const Txn(
              id: 2,
              date: '2026-01-10',
              desc: 'in2',
              acct: 'Revolut',
              out: 0,
              in_: 100),
          const Txn(
              id: 3,
              date: '2026-01-15',
              desc: 'out1',
              acct: 'Revolut',
              out: 100,
              in_: 0),
        ],
      );
      // in1's 100 is fully consumed by out1; oldest remaining bucket is
      // in2 dated 2026-01-10 -> as of 2026-01-20 that's 10 days old.
      expect(Calculations.ageOfMoney(data, '2026-01-20'), 10);
    });

    test(
        'injects the opening balance as a virtual bucket at the earliest txn date',
        () {
      final data = _dataWith(
        balances: const Balances(rev: 50),
        txns: [
          const Txn(
              id: 1,
              date: '2026-01-01',
              desc: 'in',
              acct: 'Revolut',
              out: 0,
              in_: 20),
          const Txn(
              id: 2,
              date: '2026-01-20',
              desc: 'out',
              acct: 'Revolut',
              out: 10,
              in_: 0),
        ],
      );
      // Virtual bucket of 50 dated 2026-01-01 absorbs the 10 outflow
      // without being exhausted, so as of 2026-01-25 the oldest surviving
      // bucket is still that virtual one, 24 days old.
      expect(Calculations.ageOfMoney(data, '2026-01-25'), 24);
    });
  });

  group('netWorthAsOf', () {
    test('splits positive/negative account balances into assets/debts', () {
      final data = _dataWith(
        balances: const Balances(rev: -20, wise: 100, swile: 5),
      );
      final snap = Calculations.netWorthAsOf(data, '2026-01-01');
      expect(snap.assets, 105);
      expect(snap.debts, 20);
      expect(snap.netWorth, 85);
    });
  });
}
