import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'package:marley/main.dart';
import 'package:marley/models/transaction.dart';
import 'package:marley/state/app_state.dart';
import 'package:marley/utils/formatters.dart';
import 'package:marley/widgets/summary_cards.dart';
import 'package:marley/widgets/transaction_tile.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    await initializeDateFormatting('pt_BR');
  });

  group('toggleCleared', () {
    test('flips cleared on an unlocked txn but never touches a locked one',
        () async {
      final appState = AppState();
      await appState.addTxn(Txn(
        id: 1,
        date: todayIso(),
        desc: 'Padaria',
        acct: 'Revolut',
        out: 5,
        in_: 0,
      ));
      await appState.addTxn(Txn(
        id: 2,
        date: todayIso(),
        desc: 'Já reconciliado',
        acct: 'Revolut',
        out: 5,
        in_: 0,
        locked: true,
      ));

      await appState.toggleCleared(1);
      expect(appState.data.txns.firstWhere((t) => t.id == 1).cleared, isTrue);
      await appState.toggleCleared(1);
      expect(appState.data.txns.firstWhere((t) => t.id == 1).cleared, isFalse);

      await appState.toggleCleared(2);
      expect(appState.data.txns.firstWhere((t) => t.id == 2).cleared, isFalse);
      expect(appState.data.txns.firstWhere((t) => t.id == 2).locked, isTrue);
    });
  });

  group('TransactionTile icons', () {
    testWidgets('shows © for cleared-but-unlocked, 🔒 for locked, never both',
        (tester) async {
      final appState = AppState();
      Widget wrap(Txn t) => MaterialApp(
            home: ChangeNotifierProvider.value(
              value: appState,
              child: Scaffold(body: TransactionTile(txn: t)),
            ),
          );

      const cleared = Txn(
        id: 1,
        date: '2026-08-01',
        desc: 'Cleared not locked',
        acct: 'Revolut',
        out: 5,
        in_: 0,
        cleared: true,
      );
      await tester.pumpWidget(wrap(cleared));
      expect(find.byIcon(Icons.copyright), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsNothing);
      expect(find.byType(Dismissible), findsOneWidget); // swipe enabled

      const locked = Txn(
        id: 2,
        date: '2026-08-01',
        desc: 'Locked',
        acct: 'Revolut',
        out: 5,
        in_: 0,
        locked: true,
      );
      await tester.pumpWidget(wrap(locked));
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.byIcon(Icons.copyright), findsNothing);
      expect(find.byType(Dismissible),
          findsNothing); // reconciled rows are immutable
    });
  });

  testWidgets(
      'description autocomplete suggests a past description and its category',
      (tester) async {
    await tester.pumpWidget(const MarleyApp());
    await tester.pumpAndSettle();

    // First transaction: pick a category manually so it becomes the memory
    // the autocomplete will draw on.
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Descrição'), 'Padaria Central');
    await tester.enterText(find.widgetWithText(TextField, 'Valor (€)'), '4.50');
    await tester.tap(find.text('Selecionar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('🥐 Boulangerie'));
    await tester.pumpAndSettle();

    final sheetScrollable1 = find
        .descendant(
            of: find.byType(DraggableScrollableSheet),
            matching: find.byType(Scrollable))
        .first;
    final salvarButton1 = find.widgetWithText(FilledButton, 'Salvar');
    await tester.scrollUntilVisible(salvarButton1, 200,
        scrollable: sheetScrollable1);
    await tester.tap(salvarButton1);
    await tester.pumpAndSettle();

    // Second transaction: typing the same prefix should surface a
    // suggestion; picking it should auto-fill the category.
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Descrição'), 'Pada');
    await tester.pumpAndSettle();

    // The suggestion renders as a ListTile; the Fluxo ledger row behind the
    // sheet also shows the same text, so scope the finder to disambiguate.
    final suggestion = find.widgetWithText(ListTile, 'Padaria Central');
    expect(suggestion, findsOneWidget);
    await tester.tap(suggestion);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ListTile, '🥐 Boulangerie'), findsOneWidget);
  });

  testWidgets('Contas FAB opens the reconcile flow for the selected account',
      (tester) async {
    await tester.pumpWidget(const MarleyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Contas'));
    await tester.pumpAndSettle();

    expect(find.text('Reconciliar'), findsOneWidget);
    await tester.tap(find.text('Reconciliar'));
    await tester.pumpAndSettle();

    expect(find.text('Reconciliar Revolut'), findsOneWidget);
    expect(find.text('Esse valor bate com o saldo real do banco?'),
        findsOneWidget);
  });

  testWidgets(
      'Contas Cleared/Uncleared card swipes between the two instead of '
      'showing a separate row', (tester) async {
    await tester.pumpWidget(const MarleyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Contas'));
    await tester.pumpAndSettle();

    expect(find.text('Working Balance'), findsOneWidget);
    expect(find.text('Cleared'), findsOneWidget);
    // No leading icon glyph on the label — just the plain word.
    expect(find.text('✓ Cleared'), findsNothing);
    expect(find.text('Uncleared'), findsNothing);

    await tester.drag(
        find.byType(SwipeableStatCard), const Offset(-300, 0));
    await tester.pumpAndSettle();

    expect(find.text('Uncleared'), findsOneWidget);
    expect(find.text('Cleared'), findsNothing);

    await tester.drag(find.byType(SwipeableStatCard), const Offset(300, 0));
    await tester.pumpAndSettle();

    expect(find.text('Cleared'), findsOneWidget);
    expect(find.text('Uncleared'), findsNothing);
  });

  testWidgets(
      'Budget category detail hides future transactions behind a toggle',
      (tester) async {
    await tester.pumpWidget(const MarleyApp());
    await tester.pumpAndSettle();

    final element = tester.element(find.byType(MaterialApp));
    final appState = Provider.of<AppState>(element, listen: false);
    final currentMonth = monthOf(todayIso());
    final futureDate = lastDayOfMonth(currentMonth);
    // Deliberately not awaited: awaiting an AppState mutation directly from
    // test code (rather than from a widget's own event handler) hangs
    // forever under `testWidgets` — `_persist()`'s `SharedPreferences`
    // call never resolves in that context (it does resolve, with a clean
    // MissingPluginException, in a plain `test()`; this looks like a
    // flutter_test binding quirk, not an app bug — `_touch()`/
    // `notifyListeners()` still run synchronously beforehand either way,
    // which is all the UI needs). A few bounded pumps let it settle.
    // ignore: unawaited_futures
    appState.addTxn(Txn(
      id: 1,
      date: futureDate,
      desc: 'Compra agendada',
      acct: 'Revolut',
      out: 30,
      in_: 0,
      cat: '💁🏻‍♂️ Nando',
    ));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    await tester.tap(find.text('Budget'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('💁🏻‍♂️ Nando'));
    await tester.pumpAndSettle();

    if (futureDate == todayIso()) {
      // Ran on the last day of the month: nothing future to hide, skip.
      return;
    }

    expect(find.text('▸ PRÓXIMOS — 1 agendados'), findsOneWidget);
    expect(find.text('Compra agendada'), findsNothing);

    await tester.tap(find.text('▸ PRÓXIMOS — 1 agendados'));
    await tester.pumpAndSettle();
    expect(find.text('Compra agendada'), findsOneWidget);
  });

  group('Fluxo future transactions ordering', () {
    testWidgets(
        'latest future date is listed above the soonest one, next to today',
        (tester) async {
      await tester.pumpWidget(const MarleyApp());
      await tester.pumpAndSettle();

      final element = tester.element(find.byType(MaterialApp));
      final appState = Provider.of<AppState>(element, listen: false);
      final currentMonth = monthOf(todayIso());
      final lateDate = lastDayOfMonth(currentMonth);
      final soonDate =
          toIso(parseIso(todayIso()).add(const Duration(days: 1)));
      if (monthOf(soonDate) != currentMonth || soonDate == lateDate) {
        // Too close to month-end to have two distinct future dates this
        // month — skip rather than flake.
        return;
      }

      // ignore: unawaited_futures
      appState.addTxn(Txn(
        id: 1,
        date: soonDate,
        desc: 'Amanhã',
        acct: 'Revolut',
        out: 10,
        in_: 0,
      ));
      // ignore: unawaited_futures
      appState.addTxn(Txn(
        id: 2,
        date: lateDate,
        desc: 'Fim do mês',
        acct: 'Revolut',
        out: 20,
        in_: 0,
      ));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final toggle = find.textContaining('PRÓXIMOS — 2 agendados');
      expect(toggle, findsOneWidget);
      await tester.tap(toggle);
      await tester.pumpAndSettle();

      final laterY = tester.getTopLeft(find.text('Fim do mês')).dy;
      final soonerY = tester.getTopLeft(find.text('Amanhã')).dy;
      expect(laterY, lessThan(soonerY));
    });
  });
}
