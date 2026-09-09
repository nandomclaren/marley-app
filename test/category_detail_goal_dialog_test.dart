import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'package:marley/models/goal.dart';
import 'package:marley/state/app_state.dart';
import 'package:marley/utils/formatters.dart';
import 'package:marley/widgets/category_detail_sheet.dart';

// Reproduces a real-device bug report: tapping "Editar meta"/"Definir meta"
// while the budget field still has focus (soft keyboard up) appeared to do
// nothing. _editGoal() used to push showDialog's route without dismissing
// the keyboard first, which can race with Android's IME close/resize
// animation and swallow the dialog. The fix unfocuses and lets that
// animation settle before opening the dialog.
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
      'tapping Definir meta with the budget field still focused opens the goal dialog',
      (tester) async {
    final appState = AppState();
    final month = todayIso().substring(0, 7);

    await tester.pumpWidget(_harness(appState, month, '📱 Forfaits Mobile'));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Orçado (€)'), '53.97');
    await tester.pump();

    await tester.tap(find.text('Definir meta'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets(
      'tapping Editar meta (existing goal) with the budget field still focused opens the goal dialog',
      (tester) async {
    final appState = AppState();
    final month = todayIso().substring(0, 7);
    unawaited(appState.setGoal(
        '📱 Forfaits Mobile', const Goal(type: 'monthly', target: 39.98)));

    await tester.pumpWidget(_harness(appState, month, '📱 Forfaits Mobile'));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Orçado (€)'), '53.97');
    await tester.pump();

    await tester.tap(find.text('Editar meta'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Meta — 📱 Forfaits Mobile'), findsOneWidget);
  });
}
