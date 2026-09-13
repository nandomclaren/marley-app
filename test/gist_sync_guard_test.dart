import 'package:flutter_test/flutter_test.dart';
import 'package:marley/data/gist_sync_service.dart';

void main() {
  group('isSuspiciousLockedDrop', () {
    test('no drop at all is never suspicious', () {
      expect(isSuspiciousLockedDrop(previous: 1114, incoming: 1114), isFalse);
    });

    test('locked count going up is never suspicious', () {
      expect(isSuspiciousLockedDrop(previous: 1114, incoming: 1163), isFalse);
    });

    test('a small drop within tolerance is not suspicious', () {
      expect(isSuspiciousLockedDrop(previous: 100, incoming: 96), isFalse);
    });

    test('a drop right at the tolerance boundary is not suspicious', () {
      expect(
          isSuspiciousLockedDrop(
              previous: 100, incoming: 100 - lockedCountDropTolerance),
          isFalse);
    });

    test('a drop one past the tolerance boundary is suspicious', () {
      expect(
          isSuspiciousLockedDrop(
              previous: 100, incoming: 100 - lockedCountDropTolerance - 1),
          isTrue);
    });

    test('reproduces the actual 2026-09-13 incident numbers', () {
      // prevLocked=1114 (reconciled through 10/09), newLocked=1043
      // (reverted to 31/08) -- a real 71-transaction regression that the
      // old size-only guard missed because the payload had *more*
      // transactions overall.
      expect(isSuspiciousLockedDrop(previous: 1114, incoming: 1043), isTrue);
    });
  });
}
