import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'package:marley/models/transaction.dart';
import 'package:marley/state/app_state.dart';
import 'package:marley/utils/formatters.dart';
import 'package:marley/widgets/category_detail_sheet.dart';

// Mirrors the harness in category_detail_goal_dialog_test.dart.
Widget _harness(AppState appState, String month, String category) {
  return ChangeNotifierProvider.value(
    value: appState,
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () =>
                CategoryDetailSheet.show(context, category: category, month: month),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    await initializeDateFormatting('pt_BR');
  });

  testWidgets(
      '"Por descrição" sums same-description transactions together, kept '
      'separate per merchant', (tester) async {
    final appState = AppState();
    const month = '2026-03';
    const cat = '🛒 Courses & Marché';
    unawaited(appState.addTxn(const Txn(
      id: 1,
      date: '2026-03-05',
      desc: 'Monoprix',
      acct: 'Revolut',
      out: 50,
      in_: 0,
      cat: cat,
    )));
    unawaited(appState.addTxn(const Txn(
      id: 2,
      date: '2026-03-15',
      desc: 'Monoprix',
      acct: 'Revolut',
      out: 30,
      in_: 0,
      cat: cat,
    )));
    unawaited(appState.addTxn(const Txn(
      id: 3,
      date: '2026-03-10',
      desc: 'Yommi',
      acct: 'Revolut',
      out: 54,
      in_: 0,
      cat: cat,
    )));

    await tester.pumpWidget(_harness(appState, month, cat));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Por descrição'), findsOneWidget);
    // 80 = 50 + 30, the two Monoprix visits summed into one row -- this
    // exact figure can only come from the grouped section, since no
    // individual transaction is €80 (the flat list below still shows the
    // original €50/€30 rows separately).
    expect(find.text(formatEurSigned(-80)), findsOneWidget);
    expect(find.text('Monoprix'), findsWidgets);
    expect(find.text('Yommi'), findsWidgets);
  });
}
