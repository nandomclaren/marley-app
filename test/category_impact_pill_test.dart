import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:marley/main.dart';

// A single big tester.pump(duration) only triggers one frame, which isn't
// enough to drive the pill's sequential await chain (forward -> delay ->
// forward -> delay -> reverse) through all its stages -- each stage only
// gets to run once a prior frame has let its await resolve. Stepping in
// small increments gives every stage its own frame to progress.
Future<void> _pumpFor(WidgetTester tester, Duration total,
    {Duration step = const Duration(milliseconds: 50)}) async {
  var elapsed = Duration.zero;
  while (elapsed < total) {
    await tester.pump(step);
    elapsed += step;
  }
}

Future<void> _tapSalvar(WidgetTester tester) async {
  final sheetScrollable = find
      .descendant(
          of: find.byType(DraggableScrollableSheet),
          matching: find.byType(Scrollable))
      .first;
  final salvarButton = find.widgetWithText(FilledButton, 'Salvar');
  await tester.scrollUntilVisible(salvarButton, 200,
      scrollable: sheetScrollable);
  await tester.tap(salvarButton);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    await initializeDateFormatting('pt_BR');
  });

  testWidgets(
      'saving a categorized transaction shows the impact pill, which '
      'disappears on its own', (tester) async {
    await tester.pumpWidget(const MarleyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Descrição'), 'Presente');
    await tester.enterText(find.widgetWithText(TextField, 'Valor (€)'), '10');
    await tester.tap(find.text('Selecionar'));
    await tester.pumpAndSettle();
    final catFinder = find.text('🙏 Dons');
    await tester.scrollUntilVisible(
      catFinder,
      200,
      scrollable: find
          .descendant(
              of: find.byType(DraggableScrollableSheet),
              matching: find.byType(Scrollable))
          .first,
    );
    await tester.tap(catFinder);
    await tester.pumpAndSettle();

    await _tapSalvar(tester);
    // Deliberately not pumpAndSettle: the pill's own animation controllers
    // (rise -> hold -> count -> hold -> fall) keep the tree "dirty" for
    // ~2s by design, so pumpAndSettle would time out waiting for it.
    await tester.pump(); // sheet starts closing, pill schedules its rise

    // Mid rise/hold-old: the pill should be up. "Disponível" only ever
    // appears inside the pill while on the Fluxo tab (the category itself
    // also reads "🙏 Dons" on the ledger row behind it, so that text isn't
    // a safe finder here — this label is).
    await _pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.text('Disponível'), findsOneWidget);

    // Well past the whole sequence (rise+hold+count+hold+fall ≈ 2000ms):
    // it should have removed itself.
    await _pumpFor(tester, const Duration(milliseconds: 2200));
    expect(find.text('Disponível'), findsNothing);
  });

  testWidgets('a transaction saved with no category shows no impact pill',
      (tester) async {
    await tester.pumpWidget(const MarleyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Descrição'), 'Café');
    await tester.enterText(find.widgetWithText(TextField, 'Valor (€)'), '3');
    await _tapSalvar(tester);
    // "Disponível" only ever appears inside the pill while on the Fluxo
    // tab (Budget's own column header lives on a different tab) — its
    // total absence here across the whole window means no pill fired.
    await _pumpFor(tester, const Duration(milliseconds: 2200));
    expect(find.text('Disponível'), findsNothing);
  });
}
