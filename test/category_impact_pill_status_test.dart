import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marley/theme/app_theme.dart';
import 'package:marley/utils/calculations.dart';
import 'package:marley/utils/formatters.dart';
import 'package:marley/widgets/category_impact_pill.dart';

// The pill's own await chain (rise -> hold -> count -> hold -> fall) needs
// several frames to progress, same reasoning as category_impact_pill_test.dart.
Future<void> _pumpFor(WidgetTester tester, Duration total,
    {Duration step = const Duration(milliseconds: 50)}) async {
  var elapsed = Duration.zero;
  while (elapsed < total) {
    await tester.pump(step);
    elapsed += step;
  }
}

Future<BuildContext> _pumpHarness(WidgetTester tester) async {
  late BuildContext capturedContext;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(builder: (context) {
        capturedContext = context;
        return const SizedBox();
      }),
    ),
  ));
  return capturedContext;
}

Color _valueColor(WidgetTester tester, double displayedValue) {
  final valueText = tester.widget<Text>(find.text(formatEur(displayedValue)));
  return valueText.style!.color!;
}

void main() {
  testWidgets(
      'color starts as the before-status color while still showing the old '
      'value (before the count animation starts)', (tester) async {
    final context = await _pumpHarness(tester);
    CategoryImpactPill.show(
      context,
      category: 'Forfaits Mobile',
      before: 10,
      after: -5,
      beforeStatus: BudgetCatStatus.ok,
      afterStatus: BudgetCatStatus.overspent,
    );
    await tester.pump();
    // Rise (400ms) + partway into hold-old (300ms, ends at 700ms): the
    // count hasn't started yet, so the displayed value is still `before`
    // and the color must still read as "ok" (green), not jump to red early.
    await _pumpFor(tester, const Duration(milliseconds: 500));

    final brightness =
        Theme.of(tester.element(find.byType(Scaffold))).brightness;
    expect(_valueColor(tester, 10), MarleyColors.green(brightness));

    // Drain the rest so no pending timer trips teardown.
    await _pumpFor(tester, const Duration(milliseconds: 1600));
  });

  testWidgets(
      'color lands on the after-status color once the count animation '
      'finishes (10 in the green counting down to -5 in the red)',
      (tester) async {
    final context = await _pumpHarness(tester);
    CategoryImpactPill.show(
      context,
      category: 'Forfaits Mobile',
      before: 10,
      after: -5,
      beforeStatus: BudgetCatStatus.ok,
      afterStatus: BudgetCatStatus.overspent,
    );
    await tester.pump();
    // Past rise (400) + hold-old (300) + count (550) = 1250ms, safely into
    // hold-new (1250-1650ms): the count has finished and settled on
    // `after`, well before the fall (1650-2000ms) starts.
    await _pumpFor(tester, const Duration(milliseconds: 1400));

    final brightness =
        Theme.of(tester.element(find.byType(Scaffold))).brightness;
    expect(_valueColor(tester, -5), MarleyColors.red(brightness));

    await _pumpFor(tester, const Duration(milliseconds: 700));
  });

  testWidgets(
      'a category that stays underfunded before and after shows amber '
      'throughout, not a fade between two different colors', (tester) async {
    final context = await _pumpHarness(tester);
    CategoryImpactPill.show(
      context,
      category: 'Vacances',
      before: 50,
      after: 60,
      beforeStatus: BudgetCatStatus.underfunded,
      afterStatus: BudgetCatStatus.underfunded,
    );
    await tester.pump();
    await _pumpFor(tester, const Duration(milliseconds: 1400));

    final brightness =
        Theme.of(tester.element(find.byType(Scaffold))).brightness;
    expect(_valueColor(tester, 60), pendingHighlightStripe(brightness));

    await _pumpFor(tester, const Duration(milliseconds: 700));
  });
}
