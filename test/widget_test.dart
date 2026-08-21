import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:marley/main.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    await initializeDateFormatting('pt_BR');
  });

  testWidgets('MarleyApp boots and shows the four tabs',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MarleyApp());
    await tester.pumpAndSettle();

    expect(find.text('Fluxo'), findsWidgets);
    expect(find.text('Budget'), findsWidgets);
    expect(find.text('Reflect'), findsWidgets);
    expect(find.text('Contas'), findsWidgets);
  });
}
