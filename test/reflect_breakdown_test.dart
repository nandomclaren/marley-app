import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'package:marley/main.dart';
import 'package:marley/models/transaction.dart';
import 'package:marley/state/app_state.dart';
import 'package:marley/utils/formatters.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    await initializeDateFormatting('pt_BR');
  });

  testWidgets(
      'Reflect: Spending Breakdown shows a total, switches month with the '
      'arrows (driving the shared selectedMonth), and drills into a '
      'category on tap', (tester) async {
    await tester.pumpWidget(const MarleyApp());
    await tester.pumpAndSettle();

    final element = tester.element(find.byType(MaterialApp));
    final appState = Provider.of<AppState>(element, listen: false);
    final month1 = appState.data.months.last;

    // ignore: unawaited_futures
    appState.addTxn(Txn(
      id: 1,
      date: '$month1-05',
      desc: 'Compra mes 1',
      acct: 'Revolut',
      out: 40,
      in_: 0,
      cat: '🛒 Courses & Marché',
    ));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // ignore: unawaited_futures
    appState.addNextMonth();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // addNextMonth()'s internal `await selectMonth(next)` sits behind an
    // `await _persist()` that never resolves in this test binding context
    // (a known SharedPreferences quirk -- see other tests in this suite),
    // so `selectedMonth` itself never updates this way. `_data.months`
    // does update synchronously though (before that first await), so read
    // the new month from there and switch to it explicitly.
    final month2 = appState.data.months.last;
    expect(month2, isNot(month1));
    // ignore: unawaited_futures
    appState.selectMonth(month2);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Back to month1, matching what Budget/Fluxo would leave selected.
    // ignore: unawaited_futures
    appState.selectMonth(month1);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    await tester.tap(find.text('Reflect'));
    await tester.pumpAndSettle();

    expect(find.text(monthLabel(month1)), findsOneWidget);
    // With a single spending category this month, the total and the row's
    // own amount both render "€ 40,00" -- at least one match confirms the
    // total figure is there.
    expect(find.text(formatEur(40)), findsWidgets);

    // Drill into the category -> opens CategoryDetailSheet.
    await tester.tap(find.text('🛒 Courses & Marché'));
    await tester.pumpAndSettle();
    expect(find.text('Compra mes 1'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Orçado (€)'), findsOneWidget);
    Navigator.of(tester.element(find.widgetWithText(TextField, 'Orçado (€)')))
        .pop();
    await tester.pumpAndSettle();

    // Switch month forward with the arrow -> drives the shared
    // selectedMonth, same as Budget/Fluxo's own picker would.
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();

    expect(appState.selectedMonth, month2);
    expect(find.text(monthLabel(month2)), findsOneWidget);
    // month2 is next month relative to "today" -- Reflect deliberately
    // excludes future-dated spending (matches the web app's `t.date <=
    // _today` filter), so an empty state here confirms the switch is real,
    // not just a stale re-render of month1's numbers.
    expect(find.text('Nenhum gasto neste mês.'), findsOneWidget);
  });
}
