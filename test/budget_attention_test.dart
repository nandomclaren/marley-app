import 'package:flutter_test/flutter_test.dart';
import 'package:marley/models/app_data.dart';
import 'package:marley/models/goal.dart';
import 'package:marley/models/transaction.dart';
import 'package:marley/state/app_state.dart';
import 'package:marley/utils/calculations.dart';

AppData _dataWith({
  Map<String, Map<String, double>> budgets = const {},
  List<Txn> txns = const [],
  Map<String, Goal> goals = const {},
}) {
  return AppData(
    lastModified: 0,
    months: budgets.keys.toList()..sort(),
    balances: const Balances(),
    txns: txns,
    budgets: budgets,
    goals: goals,
  );
}

void main() {
  group('Calculations.budgetStatusFor', () {
    test('no budget, no goal, nothing spent -> ok', () {
      final data = _dataWith(budgets: const {
        '2026-03': {},
      });
      expect(Calculations.budgetStatusFor(data, '🙏 Dons', '2026-03'),
          BudgetCatStatus.ok);
    });

    test('spent more than available -> overspent', () {
      final data = _dataWith(
        budgets: const {
          '2026-03': {'🙏 Dons': 50},
        },
        txns: const [
          Txn(
              id: 1,
              date: '2026-03-05',
              desc: 'x',
              acct: 'Revolut',
              out: 80,
              in_: 0,
              cat: '🙏 Dons'),
        ],
      );
      expect(Calculations.budgetStatusFor(data, '🙏 Dons', '2026-03'),
          BudgetCatStatus.overspent);
    });

    test('goal not yet met, not overspent -> underfunded', () {
      final data = _dataWith(
        budgets: const {
          '2026-03': {'🙏 Dons': 50},
        },
        goals: const {
          '🙏 Dons': Goal(type: 'monthly', target: 100),
        },
      );
      expect(Calculations.budgetStatusFor(data, '🙏 Dons', '2026-03'),
          BudgetCatStatus.underfunded);
    });

    test('goal fully met -> ok, not underfunded', () {
      final data = _dataWith(
        budgets: const {
          '2026-03': {'🙏 Dons': 100},
        },
        goals: const {
          '🙏 Dons': Goal(type: 'monthly', target: 100),
        },
      );
      expect(Calculations.budgetStatusFor(data, '🙏 Dons', '2026-03'),
          BudgetCatStatus.ok);
    });

    test('overspent takes priority over an unmet goal', () {
      final data = _dataWith(
        budgets: const {
          '2026-03': {'🙏 Dons': 50},
        },
        goals: const {
          '🙏 Dons': Goal(type: 'monthly', target: 100),
        },
        txns: const [
          Txn(
              id: 1,
              date: '2026-03-05',
              desc: 'x',
              acct: 'Revolut',
              out: 90,
              in_: 0,
              cat: '🙏 Dons'),
        ],
      );
      expect(Calculations.budgetStatusFor(data, '🙏 Dons', '2026-03'),
          BudgetCatStatus.overspent);
    });

    test('no budget but has a target_date goal via monthlyContrib', () {
      final data = _dataWith(
        budgets: const {'2026-03': {}},
        goals: const {
          '🏝️ Vacances': Goal(
              type: 'target_date',
              target: 2000,
              targetDate: '2026-12-01',
              monthlyContrib: 200),
        },
      );
      expect(Calculations.budgetStatusFor(data, '🏝️ Vacances', '2026-03'),
          BudgetCatStatus.underfunded);
    });
  });

  group('AppState device preferences', () {
    test('setHomeScreen updates the field', () async {
      final appState = AppState();
      expect(appState.homeScreen, 'fluxo');
      await appState.setHomeScreen('budget');
      expect(appState.homeScreen, 'budget');
    });

    test('setAttentionGroupEnabled updates the field', () async {
      final appState = AppState();
      expect(appState.attentionGroupEnabled, isFalse);
      await appState.setAttentionGroupEnabled(true);
      expect(appState.attentionGroupEnabled, isTrue);
    });
  });
}
