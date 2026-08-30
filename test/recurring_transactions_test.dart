import 'package:flutter_test/flutter_test.dart';
import 'package:marley/models/app_data.dart';
import 'package:marley/models/transaction.dart';
import 'package:marley/state/app_state.dart';
import 'package:marley/utils/calculations.dart';

AppData _dataWith({
  List<String> months = const [],
  List<Txn> txns = const [],
  Map<String, Map<String, double>> budgets = const {},
  Map<String, List<String>> skipRecurring = const {},
}) {
  return AppData(
    lastModified: 0,
    months: months,
    balances: const Balances(),
    txns: txns,
    budgets: budgets,
    goals: const {},
    skipRecurring: skipRecurring,
  );
}

void main() {
  group('Calculations.autoGenerateRecurringTxns', () {
    test('copies a fixed transaction from last month forward a month',
        () async {
      final data = _dataWith(
        months: const ['2026-08', '2026-09'],
        txns: const [
          Txn(
            id: 1,
            date: '2026-08-01',
            desc: '🏠 Bail',
            acct: 'Revolut',
            out: 2800,
            in_: 0,
            style: 'fixed',
          ),
        ],
      );

      final generated =
          Calculations.autoGenerateRecurringTxns(data, '2026-09');

      expect(generated, hasLength(1));
      expect(generated.single.date, '2026-09-01');
      expect(generated.single.desc, '🏠 Bail');
      expect(generated.single.cleared, isFalse);
      expect(generated.single.locked, isFalse);
      expect(generated.single.id, 2); // next free id after the seed txn
    });

    test('clamps the day to the target month\'s last day', () async {
      final data = _dataWith(
        months: const ['2026-01', '2026-02'],
        txns: const [
          Txn(
            id: 1,
            date: '2026-01-31',
            desc: '📱 Assinatura',
            acct: 'Revolut',
            out: 10,
            in_: 0,
            style: 'fixed',
          ),
        ],
      );

      final generated =
          Calculations.autoGenerateRecurringTxns(data, '2026-02');

      expect(generated.single.date, '2026-02-28'); // 2026 is not a leap year
    });

    test('never regenerates a plain one-off transaction', () async {
      final data = _dataWith(
        months: const ['2026-08', '2026-09'],
        txns: const [
          Txn(
            id: 1,
            date: '2026-08-05',
            desc: '🥨 Pretzel',
            acct: 'Revolut',
            out: 3,
            in_: 0,
            style: 'normal',
          ),
        ],
      );

      expect(Calculations.autoGenerateRecurringTxns(data, '2026-09'), isEmpty);
    });

    test('never copies the opening-balance row even if flagged recurring',
        () async {
      final data = _dataWith(
        months: const ['2026-08', '2026-09'],
        txns: const [
          Txn(
            id: 1,
            date: '2026-08-01',
            desc: 'Saldo Inicial',
            acct: '—',
            out: 0,
            in_: 0,
            style: 'opening',
            recurring: true,
          ),
        ],
      );

      expect(Calculations.autoGenerateRecurringTxns(data, '2026-09'), isEmpty);
    });

    test('skips a description already present in the target month',
        () async {
      final data = _dataWith(
        months: const ['2026-08', '2026-09'],
        txns: const [
          Txn(
            id: 1,
            date: '2026-08-01',
            desc: '🏠 Bail',
            acct: 'Revolut',
            out: 2800,
            in_: 0,
            style: 'fixed',
          ),
          Txn(
            id: 2,
            date: '2026-09-03',
            desc: '🏠 Bail',
            acct: 'Revolut',
            out: 2800,
            in_: 0,
            style: 'fixed',
          ),
        ],
      );

      expect(Calculations.autoGenerateRecurringTxns(data, '2026-09'), isEmpty);
    });

    test('respects a description explicitly skipped for the target month',
        () async {
      final data = _dataWith(
        months: const ['2026-08', '2026-09'],
        txns: const [
          Txn(
            id: 1,
            date: '2026-08-01',
            desc: '🏠 Bail',
            acct: 'Revolut',
            out: 2800,
            in_: 0,
            style: 'fixed',
          ),
        ],
        skipRecurring: const {
          '2026-09': ['🏠 Bail'],
        },
      );

      expect(Calculations.autoGenerateRecurringTxns(data, '2026-09'), isEmpty);
    });
  });

  group('Calculations.toBeBudgeted ("A Alocar")', () {
    test('received income minus everything ever allocated', () async {
      final data = _dataWith(
        months: const ['2026-03'],
        txns: const [
          Txn(
              id: 1,
              date: '2026-03-01',
              desc: 'Salário',
              acct: 'Revolut',
              out: 0,
              in_: 3000),
          // Before the startup floor date — must not count.
          Txn(
              id: 2,
              date: '2026-02-10',
              desc: 'Antigo',
              acct: 'Revolut',
              out: 0,
              in_: 500),
          // Opening balance — must not count even though in_ > 0.
          Txn(
              id: 3,
              date: '2026-03-02',
              desc: 'Saldo Inicial',
              acct: '—',
              out: 0,
              in_: 1000,
              style: 'opening'),
        ],
        budgets: const {
          '2026-03': {'🛒 Courses': 400, '💸 Bail': 2800},
          // At/before the floor month — must not count.
          '2026-02': {'x': 999},
        },
      );

      expect(Calculations.toBeBudgeted(data, asOf: '2026-03-31'), 3000 - 3200);
    });

    test('only counts income received up to asOf', () async {
      final data = _dataWith(
        months: const ['2026-03'],
        txns: const [
          Txn(
              id: 1,
              date: '2026-03-01',
              desc: 'Salário',
              acct: 'Revolut',
              out: 0,
              in_: 3000),
          Txn(
              id: 2,
              date: '2026-03-20',
              desc: 'Reembolso futuro',
              acct: 'Revolut',
              out: 0,
              in_: 500),
        ],
        budgets: const {},
      );

      expect(Calculations.toBeBudgeted(data, asOf: '2026-03-10'), 3000);
    });
  });

  group('AppState wires recurring generation into month switching', () {
    test('addNextMonth (the "+ mês" button) materializes fixed txns forward',
        () async {
      final appState = AppState();
      final baseMonth = appState.data.months.last;
      await appState.addTxn(Txn(
        id: 1,
        date: '$baseMonth-05',
        desc: '💡 Électricité',
        acct: 'Revolut',
        out: 180,
        in_: 0,
        style: 'fixed',
      ));

      await appState.addNextMonth();

      final nextMonth = appState.selectedMonth;
      expect(nextMonth, isNot(baseMonth));
      final carriedOver = appState.data.txns
          .where((t) =>
              t.date.startsWith(nextMonth) && t.desc == '💡 Électricité')
          .toList();
      expect(carriedOver, hasLength(1));
      expect(carriedOver.single.cleared, isFalse);
      expect(carriedOver.single.locked, isFalse);
    });

    test('deleting a recurring txn records a skip that survives regeneration',
        () async {
      final appState = AppState();
      await appState.addTxn(const Txn(
        id: 1,
        date: '2026-08-01',
        desc: '💡 Électricité',
        acct: 'Revolut',
        out: 180,
        in_: 0,
        style: 'fixed',
      ));
      await appState.deleteTxn(1);

      expect(
          appState.data.skipRecurring['2026-08'], contains('💡 Électricité'));
    });
  });
}
