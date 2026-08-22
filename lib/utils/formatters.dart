import 'package:intl/intl.dart';

// Note: visually this matches the web app's custom formatter — "€ 1.234,56"
// (symbol first, dot thousands separator, comma decimals) — which is the
// pt_BR grouping style, not true fr_FR (which would read "1 234,56 €").
final NumberFormat _eurFormat = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: '€',
  decimalDigits: 2,
);

/// Formats a value as EUR, e.g. "€ 1.234,56".
String formatEur(double value) => _eurFormat.format(value);

String formatEurSigned(double value) {
  final formatted = formatEur(value.abs());
  if (value > 0) return '+$formatted';
  if (value < 0) return '-$formatted';
  return formatted;
}

final DateFormat _isoDate = DateFormat('yyyy-MM-dd');
final DateFormat _displayDate = DateFormat('d MMM', 'fr_FR');
final DateFormat _monthLabel = DateFormat('MMMM', 'pt_BR');

String todayIso() => _isoDate.format(DateTime.now());

String toIso(DateTime d) => _isoDate.format(d);

DateTime parseIso(String iso) => DateTime.parse(iso);

String displayDate(String iso) => _displayDate.format(DateTime.parse(iso));

/// 'YYYY-MM' -> capitalized month label, e.g. '2026-03' -> 'Março'.
String monthLabel(String yyyymm) {
  final parts = yyyymm.split('-');
  final year = int.parse(parts[0]);
  final month = int.parse(parts[1]);
  final label = _monthLabel.format(DateTime(year, month, 1));
  return label[0].toUpperCase() + label.substring(1);
}

String nextMonth(String yyyymm) {
  final parts = yyyymm.split('-');
  var year = int.parse(parts[0]);
  var month = int.parse(parts[1]) + 1;
  if (month > 12) {
    month = 1;
    year++;
  }
  return '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';
}

/// Last calendar day of a 'YYYY-MM' month, as an ISO date string.
String lastDayOfMonth(String yyyymm) {
  final parts = yyyymm.split('-');
  final year = int.parse(parts[0]);
  final month = int.parse(parts[1]);
  final firstOfNext =
      (month == 12) ? DateTime(year + 1, 1, 1) : DateTime(year, month + 1, 1);
  final last = firstOfNext.subtract(const Duration(days: 1));
  return toIso(last);
}

String monthOf(String iso) => iso.substring(0, 7);

final RegExp _leadingSymbols = RegExp(r'^[^\p{L}\p{N}]+', unicode: true);

/// Strips any leading emoji/symbols (e.g. the category glyph some
/// descriptions are prefixed with) and lowercases, for description
/// matching/autocomplete. Matches the web app's `bareDesc`.
String bareDesc(String s) =>
    s.replaceFirst(_leadingSymbols, '').toLowerCase().trim();
