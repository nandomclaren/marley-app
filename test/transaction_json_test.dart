import 'package:flutter_test/flutter_test.dart';
import 'package:marley/models/transaction.dart';

void main() {
  group('Txn JSON', () {
    test('reads the "in_" key (with trailing underscore), matching the web app',
        () {
      // The web app's own JS objects use `in_` as the literal property name
      // — `in` is a reserved word in JavaScript — so that's what actually
      // gets written to the Gist. Regression test for a real bug where the
      // Dart port read/wrote plain "in", silently zeroing every inflow
      // after a sync and blowing up every downstream balance.
      final json = {
        'id': 1,
        'date': '2026-02-25',
        'desc': 'Salário',
        'acct': 'Revolut',
        'out': 0,
        'in_': 8097,
        'notes': '',
        'style': 'salary',
        'recurring': true,
        'warning': false,
        'cat': '',
      };
      final txn = Txn.fromJson(json);
      expect(txn.in_, 8097);
    });

    test('round-trips through toJson/fromJson', () {
      const txn = Txn(
        id: 42,
        date: '2026-03-01',
        desc: 'Bail',
        acct: 'Revolut',
        out: 2800,
        in_: 0,
        style: 'critical',
        cat: '💸 Bail',
      );
      final roundTripped = Txn.fromJson(txn.toJson());
      expect(roundTripped.in_, txn.in_);
      expect(roundTripped.out, txn.out);
      expect(txn.toJson()['in_'], 0);
      expect(txn.toJson().containsKey('in'), isFalse);
    });
  });
}
