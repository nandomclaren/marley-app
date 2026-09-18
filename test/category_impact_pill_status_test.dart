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

Future<Color> _showAndReadValueColor(
    WidgetTester tester, BudgetCatStatus status) async {
  late BuildContext capturedContext;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(builder: (context) {
        capturedContext = context;
        return const SizedBox();
      }),
    ),
  ));

  CategoryImpactPill.show(capturedContext,
      category: 'Test', before: 10, after: 20, status: status);
  await tester.pump();
  // Past rise (400ms) + hold-old (300ms) + count (550ms) = 1250ms, safely
  // into hold-new (1250-1650ms) where the count animation has finished and
  // settled on `after`, well before the fall (1650-2000ms) starts.
  await _pumpFor(tester, const Duration(milliseconds: 1400));

  final valueText = tester.widget<Text>(find.text(formatEur(20)));
  final color = valueText.style!.color!;

  // Drain the rest of the sequence (fall + onDone) so no Future.delayed
  // timer is left pending when the test tears down the widget tree.
  await _pumpFor(tester, const Duration(milliseconds: 700));
  return color;
}

void main() {
  testWidgets('overspent category renders the pill value in red',
      (tester) async {
    final color =
        await _showAndReadValueColor(tester, BudgetCatStatus.overspent);
    final brightness = Theme.of(
            tester.element(find.byType(Scaffold)))
        .brightness;
    expect(color, MarleyColors.red(brightness));
  });

  testWidgets('underfunded category renders the pill value in amber',
      (tester) async {
    final color =
        await _showAndReadValueColor(tester, BudgetCatStatus.underfunded);
    final brightness = Theme.of(
            tester.element(find.byType(Scaffold)))
        .brightness;
    expect(color, pendingHighlightStripe(brightness));
  });

  testWidgets('ok category with a nonzero balance renders the pill value in green',
      (tester) async {
    final color = await _showAndReadValueColor(tester, BudgetCatStatus.ok);
    final brightness = Theme.of(
            tester.element(find.byType(Scaffold)))
        .brightness;
    expect(color, MarleyColors.green(brightness));
  });
}
