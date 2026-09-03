import 'package:flutter_test/flutter_test.dart';
import 'package:marley/models/app_data.dart';
import 'package:marley/models/transaction.dart';
import 'package:marley/utils/calculations.dart';

AppData _dataWith({
  Balances balances = const Balances(),
  List<Txn> txns = const [],
}) {
  return AppData(
    lastModified: 0,
    months: const [],
    balances: balances,
    txns: txns,
    budgets: const {},
    goals: const {},
  );
}

void main() {
  group('Contas header balances (Working / Cleared / Uncleared)', () {
    // Regression for the Contas screen's old "Saldo atual", which walked
    // the running balance across *every* transaction on the account —
    // including future-dated and never-cleared ones — and so disagreed
    // wildly with what the reconcile flow showed for the exact same
    // account. These three now share the same up-to-today, account-scoped
    // building blocks the reconcile flow already used.
    test('cleared + uncleared always sums to the working balance', () async {
      final data = _dataWith(
        balances: const Balances(rev: 1000),
        txns: const [
          Txn(
              id: 1,
              date: '2026-03-01',
              desc: 'Aluguel',
              acct: 'Revolut',
              out: 200,
              in_: 0,
              cleared: true),
          Txn(
              id: 2,
              date: '2026-03-02',
              desc: 'Salário',
              acct: 'Revolut',
              out: 0,
              in_: 500,
              locked: true),
          Txn(
              id: 3,
              date: '2026-03-03',
              desc: 'Mercado',
              acct: 'Revolut',
              out: 50,
              in_: 0), // neither cleared nor locked
        ],
      );

      final working = Calculations.workingBalanceForAccount(data, 'Revolut',
          asOf: '2026-03-31');
      final cleared = Calculations.clearedBalanceForAccount(data, 'Revolut',
          asOf: '2026-03-31');
      final uncleared = Calculations.unclearedNetForAccount(data, 'Revolut',
          asOf: '2026-03-31');

      expect(cleared, 1000 - 200 + 500); // opening + cleared + locked
      expect(uncleared, -50); // the one uncleared, unlocked row
      expect(working, cleared + uncleared);
    });

    test('future-dated transactions never move any of the three balances',
        () async {
      final data = _dataWith(
        balances: const Balances(rev: 100),
        txns: const [
          Txn(
              id: 1,
              date: '2026-03-01',
              desc: 'Já aconteceu',
              acct: 'Revolut',
              out: 10,
              in_: 0,
              cleared: true),
          Txn(
              id: 2,
              date: '2099-01-01',
              desc: 'Agendada pro futuro',
              acct: 'Revolut',
              out: 999,
              in_: 0,
              cleared: true),
        ],
      );

      final working = Calculations.workingBalanceForAccount(data, 'Revolut',
          asOf: '2026-03-01');
      final cleared = Calculations.clearedBalanceForAccount(data, 'Revolut',
          asOf: '2026-03-01');

      expect(cleared, 100 - 10);
      expect(working, 100 - 10);
    });

    test('the opening-balance row itself is never double-counted', () async {
      final data = _dataWith(
        balances: const Balances(rev: 100),
        txns: const [
          Txn(
              id: 1,
              date: '2026-03-01',
              desc: 'Saldo Inicial',
              acct: 'Revolut',
              out: 0,
              in_: 100,
              style: 'opening',
              cleared: true,
              locked: true),
        ],
      );

      expect(
          Calculations.clearedBalanceForAccount(data, 'Revolut',
              asOf: '2026-03-31'),
          100);
    });

    test('only counts transactions on the requested account', () async {
      final data = _dataWith(
        balances: const Balances(rev: 100, wise: 50),
        txns: const [
          Txn(
              id: 1,
              date: '2026-03-01',
              desc: 'Wise expense',
              acct: 'Wise',
              out: 20,
              in_: 0,
              cleared: true),
        ],
      );

      expect(
          Calculations.clearedBalanceForAccount(data, 'Revolut',
              asOf: '2026-03-31'),
          100);
      expect(
          Calculations.clearedBalanceForAccount(data, 'Wise',
              asOf: '2026-03-31'),
          30);
    });
  });
}
