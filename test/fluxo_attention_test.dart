import 'package:flutter_test/flutter_test.dart';
import 'package:marley/models/app_data.dart';
import 'package:marley/models/transaction.dart';
import 'package:marley/state/app_state.dart';
import 'package:marley/utils/calculations.dart';

void main() {
  group('Calculations.compareForDailyAttention', () {
    const pendingManual = Txn(
      id: 10,
      date: '2026-09-03',
      desc: 'Táxi',
      acct: 'Revolut',
      out: 38,
      in_: 0,
      addedManually: true,
    );
    const pendingOther = Txn(
      id: 5,
      date: '2026-09-03',
      desc: 'Netflix',
      acct: 'Revolut',
      out: 19.9,
      in_: 0,
    );
    const settledRecent = Txn(
      id: 3,
      date: '2026-09-03',
      desc: 'Monoprix',
      acct: 'Revolut',
      out: 24.1,
      in_: 0,
      cleared: true,
      settledAt: 2000,
    );
    const settledOld = Txn(
      id: 2,
      date: '2026-09-03',
      desc: 'Lefties',
      acct: 'Revolut',
      out: 54.94,
      in_: 0,
      locked: true,
      settledAt: 1000,
    );
    const settledNoTimestamp = Txn(
      id: 1,
      date: '2026-09-03',
      desc: 'Saldo Inicial',
      acct: '—',
      out: 0,
      in_: 0,
      locked: true,
    );

    test('sorts by date descending first, across everything else', () {
      const earlier = Txn(
          id: 99,
          date: '2026-09-01',
          desc: 'x',
          acct: 'Revolut',
          out: 1,
          in_: 0,
          addedManually: true);
      final rows = [earlier, pendingOther]
        ..sort(Calculations.compareForDailyAttention);
      expect(rows, [pendingOther, earlier]);
    });

    test('pending rows come before settled rows on the same day', () {
      final rows = [settledRecent, pendingOther]
        ..sort(Calculations.compareForDailyAttention);
      expect(rows, [pendingOther, settledRecent]);
    });

    test(
        'among pending rows, manually-added comes first, then most '
        'recently added (higher id)', () {
      const olderManual = Txn(
        id: 1,
        date: '2026-09-03',
        desc: 'Old manual',
        acct: 'Revolut',
        out: 1,
        in_: 0,
        addedManually: true,
      );
      final rows = [pendingOther, olderManual, pendingManual]
        ..sort(Calculations.compareForDailyAttention);
      // Both manual entries outrank the non-manual one; the more recently
      // added manual entry (higher id) outranks the older manual one.
      expect(rows, [pendingManual, olderManual, pendingOther]);
    });

    test(
        'among settled rows, most recently settled comes first; missing '
        'settledAt sorts last', () {
      final rows = [settledOld, settledNoTimestamp, settledRecent]
        ..sort(Calculations.compareForDailyAttention);
      expect(rows, [settledRecent, settledOld, settledNoTimestamp]);
    });

    test('full day: pending (manual, then others) above settled (newest '
        'settle first)', () {
      final rows = [
        settledOld,
        pendingOther,
        settledNoTimestamp,
        settledRecent,
        pendingManual,
      ]..sort(Calculations.compareForDailyAttention);
      expect(rows, [
        pendingManual,
        pendingOther,
        settledRecent,
        settledOld,
        settledNoTimestamp,
      ]);
    });
  });

  group('AppState wires addedManually / settledAt', () {
    test('addTxn always marks the row as manually added', () async {
      final appState = AppState();
      await appState.addTxn(const Txn(
        id: 1,
        date: '2026-09-03',
        desc: 'Táxi',
        acct: 'Revolut',
        out: 38,
        in_: 0,
        // Deliberately passing false — addTxn must override this; nothing
        // that reaches the ledger any other way should be able to claim
        // manual-add status by accident either.
        addedManually: false,
      ));

      expect(appState.data.txns.single.addedManually, isTrue);
    });

    test('toggleCleared stamps settledAt on, then clears it back off',
        () async {
      final appState = AppState();
      await appState.addTxn(const Txn(
        id: 1,
        date: '2026-09-03',
        desc: 'Netflix',
        acct: 'Revolut',
        out: 19.9,
        in_: 0,
      ));

      await appState.toggleCleared(1);
      final cleared = appState.data.txns.single;
      expect(cleared.cleared, isTrue);
      expect(cleared.settledAt, isNotNull);

      await appState.toggleCleared(1);
      final uncleared = appState.data.txns.single;
      expect(uncleared.cleared, isFalse);
      expect(uncleared.settledAt, isNull);
    });

    test('reconcileAccount stamps settledAt on every row it locks, and on '
        'the correction row', () async {
      final appState = AppState();
      await appState.addTxn(const Txn(
        id: 1,
        date: '2026-09-03',
        desc: 'Monoprix',
        acct: 'Revolut',
        out: 24.1,
        in_: 0,
      ));
      await appState.toggleCleared(1); // now cleared, unlocked

      await appState.reconcileAccount(
        acct: 'Revolut',
        realBalance: -100,
        clearedBalanceBefore: -24.1,
      );

      final locked = appState.data.txns.firstWhere((t) => t.id == 1);
      expect(locked.locked, isTrue);
      expect(locked.settledAt, isNotNull);

      final correction =
          appState.data.txns.firstWhere((t) => t.desc.contains('correção'));
      expect(correction.locked, isTrue);
      expect(correction.settledAt, isNotNull);
    });
  });

  group('Txn JSON round-trips the new fields', () {
    test('addedManually and settledAt survive toJson/fromJson', () {
      const data = AppData(
        lastModified: 0,
        months: [],
        balances: Balances(),
        txns: [
          Txn(
            id: 1,
            date: '2026-09-03',
            desc: 'Táxi',
            acct: 'Revolut',
            out: 38,
            in_: 0,
            addedManually: true,
            settledAt: 12345,
          ),
        ],
        budgets: {},
        goals: {},
      );

      final roundTripped = AppData.fromJson(data.toJson());
      final t = roundTripped.txns.single;
      expect(t.addedManually, isTrue);
      expect(t.settledAt, 12345);
    });

    test('absent fields default to false/null (older Gist data)', () {
      final t = Txn.fromJson({
        'id': 1,
        'date': '2026-09-03',
        'desc': 'Old row',
        'acct': 'Revolut',
        'out': 1,
        'in_': 0,
      });
      expect(t.addedManually, isFalse);
      expect(t.settledAt, isNull);
    });
  });
}
