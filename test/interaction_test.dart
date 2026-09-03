import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:marley/main.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    await initializeDateFormatting('pt_BR');
  });

  testWidgets('add a transaction from Fluxo and see it in the ledger',
      (tester) async {
    await tester.pumpWidget(const MarleyApp());
    await tester.pumpAndSettle();

    // Open the add-transaction sheet.
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Descrição'), 'Café');
    await tester.enterText(find.widgetWithText(TextField, 'Valor (€)'), '4.50');

    // The sheet is a scrollable DraggableScrollableSheet; the Salvar button
    // is below the fold until we scroll it into view.
    final sheetScrollable = find
        .descendant(
          of: find.byType(DraggableScrollableSheet),
          matching: find.byType(Scrollable),
        )
        .first;
    final salvarButton = find.widgetWithText(FilledButton, 'Salvar');
    await tester.scrollUntilVisible(salvarButton, 200,
        scrollable: sheetScrollable);
    await tester.tap(salvarButton);
    await tester.pumpAndSettle();

    expect(find.text('Café'), findsOneWidget);
  });

  testWidgets('switching tabs shows Budget, Reflect and Contas without errors',
      (tester) async {
    await tester.pumpWidget(const MarleyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Budget'));
    await tester.pumpAndSettle();
    expect(find.text('Categoria'), findsOneWidget);

    await tester.tap(find.text('Reflect'));
    await tester.pumpAndSettle();
    expect(find.text('Reflect'), findsWidgets);

    await tester.tap(find.text('Contas'));
    await tester.pumpAndSettle();
    expect(find.text('Working Balance'), findsOneWidget);
  });

  testWidgets('tapping a Budget category opens its detail sheet',
      (tester) async {
    await tester.pumpWidget(const MarleyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Budget'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('💁🏻‍♂️ Nando'));
    await tester.pumpAndSettle();

    expect(find.text('Orçado (€)'), findsOneWidget);
    expect(find.text('Transações do mês'), findsOneWidget);
  });
}
