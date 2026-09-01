import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/categories.dart';
import '../models/app_data.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/calculations.dart';
import '../utils/formatters.dart';
import '../widgets/sync_button.dart';

/// '2026-02' is always excluded from Reflect — it was the app's startup
/// month (mid-month, incomplete data). Matches the web app's literal
/// `mo2 !== '2026-02'` check, not "any February".
bool _isFebruary(String yyyymm) => yyyymm == '2026-02';

class ReflectScreen extends StatefulWidget {
  const ReflectScreen({super.key});

  @override
  State<ReflectScreen> createState() => _ReflectScreenState();
}

class _ReflectScreenState extends State<ReflectScreen> {
  String? _breakdownMonth;
  bool _breakdownExpanded = false;
  String? _netWorthMonth;

  List<String> _eligibleMonths(AppData data) {
    final months = data.months.where((m) => !_isFebruary(m)).toList()..sort();
    return months;
  }

  List<String> _last6(List<String> months) {
    if (months.length <= 6) return months;
    return months.sublist(months.length - 6);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final data = appState.data;
    final eligible = _eligibleMonths(data);

    if (eligible.isEmpty) {
      return Scaffold(
        appBar: AppBar(
            title: const Text('Reflect'),
            actions: const [SyncButton(), SizedBox(width: 4)]),
        body: const Center(child: Text('Sem dados suficientes ainda.')),
      );
    }

    final last6 = _last6(eligible);
    _breakdownMonth ??= (eligible.contains(appState.selectedMonth)
        ? appState.selectedMonth
        : eligible.last);
    if (_isFebruary(_breakdownMonth!)) _breakdownMonth = eligible.last;
    _netWorthMonth ??= last6.last;

    return Scaffold(
      appBar: AppBar(
          title: const Text('Reflect'),
          actions: const [SyncButton(), SizedBox(width: 4)]),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _SectionCard(
            title: 'Spending Breakdown',
            subtitle: monthLabel(_breakdownMonth!),
            child: _SpendingBreakdown(
              data: data,
              month: _breakdownMonth!,
              expanded: _breakdownExpanded,
              onToggle: () =>
                  setState(() => _breakdownExpanded = !_breakdownExpanded),
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Income vs Spending',
            subtitle: 'Últimos ${last6.length} meses',
            child: _IncomeVsSpendingChart(data: data, months: last6),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Net Worth',
            subtitle: monthLabel(_netWorthMonth!),
            child: _NetWorthSection(
              data: data,
              months: last6,
              selected: _netWorthMonth!,
              onSelect: (m) => setState(() => _netWorthMonth = m),
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Age of Money',
            subtitle: () {
              final aom = Calculations.ageOfMoney(data, todayIso());
              return aom == null ? '--' : '$aom dias';
            }(),
            child: _AgeOfMoneyChart(data: data, months: last6),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _SectionCard(
      {required this.title, required this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MarleyColors.bgCard(brightness),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _SpendingBreakdown extends StatelessWidget {
  final AppData data;
  final String month;
  final bool expanded;
  final VoidCallback onToggle;

  const _SpendingBreakdown({
    required this.data,
    required this.month,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final entries = <MapEntry<String, double>>[];
    for (final cat in kAllCategories) {
      final spent = Calculations.reflectSpentForCategory(data, month, cat);
      if (spent > 0) entries.add(MapEntry(cat, spent));
    }
    entries.sort((a, b) => b.value.compareTo(a.value));

    if (entries.isEmpty) {
      return const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('Nenhum gasto neste mês.'));
    }

    final total = entries.fold(0.0, (a, e) => a + e.value);

    List<MapEntry<String, double>> shown;
    double? othersTotal;
    if (!expanded && entries.length > 5) {
      shown = entries.take(5).toList();
      othersTotal = entries.skip(5).fold<double>(0.0, (a, e) => a + e.value);
    } else {
      shown = entries;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 14,
            child: Row(
              children: [
                for (final e in shown)
                  Expanded(
                    flex: _asFlex(e.value),
                    child: Container(color: colorForCategory(e.key)),
                  ),
                if (othersTotal != null && othersTotal > 0)
                  Expanded(
                    flex: _asFlex(othersTotal),
                    child: Container(color: Colors.grey),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final e in shown)
          _breakdownRow(
              context, e.key, e.value, total, colorForCategory(e.key)),
        if (othersTotal != null && othersTotal > 0)
          _breakdownRow(context, 'Outros', othersTotal, total, Colors.grey),
        if (entries.length > 5)
          TextButton(
            onPressed: onToggle,
            child: Text(expanded ? 'Ver menos' : 'Ver todas as categorias'),
          ),
      ],
    );
  }

  Widget _breakdownRow(BuildContext context, String label, double value,
      double total, Color color) {
    final pct = total == 0 ? 0.0 : (value / total * 100);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
          Text('${pct.toStringAsFixed(0)}%',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(width: 8),
          SizedBox(
              width: 80,
              child: Text(formatEur(value), textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}

class _IncomeVsSpendingChart extends StatelessWidget {
  final AppData data;
  final List<String> months;

  const _IncomeVsSpendingChart({required this.data, required this.months});

  @override
  Widget build(BuildContext context) {
    final incomes =
        months.map((m) => Calculations.totalIncome(data, m)).toList();
    final spendings =
        months.map((m) => Calculations.totalOutflow(data, m)).toList();
    final maxY =
        [...incomes, ...spendings].fold(0.0, (a, b) => b > a ? b : a) * 1.2 + 1;

    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          maxY: maxY,
          alignment: BarChartAlignment.spaceAround,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: _barTooltipData(),
          ),
          titlesData: FlTitlesData(
            leftTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= months.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_shortMonth(months[i]),
                        style: const TextStyle(fontSize: 10)),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < months.length; i++)
              BarChartGroupData(
                x: i,
                barsSpace: 4,
                barRods: [
                  BarChartRodData(
                    toY: incomes[i],
                    color: MarleyColors.incomeGreen,
                    width: 10,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  BarChartRodData(
                    toY: spendings[i],
                    color: MarleyColors.spendingPurple,
                    width: 10,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _NetWorthSection extends StatelessWidget {
  final AppData data;
  final List<String> months;
  final String selected;
  final ValueChanged<String> onSelect;

  const _NetWorthSection({
    required this.data,
    required this.months,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final values =
        months.map((m) => Calculations.netWorthForMonth(data, m)).toList();
    final maxVal = values.fold(0.0, (a, b) => b.abs() > a ? b.abs() : a);
    final maxY = maxVal * 1.3 + 1;
    final minY = -maxY * 0.2;
    final selectedIndex = months.indexOf(selected);

    final snap = Calculations.netWorthAsOf(data, lastDayOfMonth(selected));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 200,
          child: BarChart(
            BarChartData(
              maxY: maxY,
              minY: minY,
              alignment: BarChartAlignment.spaceAround,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: _barTooltipData(),
                touchCallback: (event, response) {
                  if (!event.isInterestedForInteractions) return;
                  final index = response?.spot?.touchedBarGroupIndex;
                  if (index != null && index >= 0 && index < months.length) {
                    onSelect(months[index]);
                  }
                },
              ),
              titlesData: FlTitlesData(
                leftTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= months.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(_shortMonth(months[i]),
                            style: const TextStyle(fontSize: 10)),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < months.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: values[i],
                        width: 18,
                        borderRadius: BorderRadius.circular(4),
                        color: i == selectedIndex
                            ? MarleyColors.spendingPurple
                                .withValues(alpha: 0.55)
                            : MarleyColors.spendingPurple
                                .withValues(alpha: 0.15),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _nwStat(
                context, 'Assets', snap.assets, Theme.of(context).brightness,
                positive: true),
            _nwStat(context, 'Debts', snap.debts, Theme.of(context).brightness,
                positive: false),
            _nwStat(context, 'Net Worth', snap.netWorth,
                Theme.of(context).brightness,
                positive: snap.netWorth >= 0),
          ],
        ),
      ],
    );
  }

  Widget _nwStat(
      BuildContext context, String label, double value, Brightness brightness,
      {required bool positive}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(
          formatEur(value),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: positive
                ? MarleyColors.green(brightness)
                : MarleyColors.red(brightness),
          ),
        ),
      ],
    );
  }
}

class _AgeOfMoneyChart extends StatelessWidget {
  final AppData data;
  final List<String> months;

  const _AgeOfMoneyChart({required this.data, required this.months});

  @override
  Widget build(BuildContext context) {
    final values = <double>[];
    for (final m in months) {
      final aom = Calculations.ageOfMoney(data, lastDayOfMonth(m));
      values.add((aom ?? 0).toDouble());
    }
    final maxY = (values.fold(0.0, (a, b) => b > a ? b : a)) * 1.3 + 1;

    final spots = [
      for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i])
    ];

    return SizedBox(
      height: 180,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (months.length - 1).toDouble().clamp(0, double.infinity),
          minY: 0,
          maxY: maxY,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (touchedSpot) => Colors.black87,
              getTooltipItems: (touchedSpots) => touchedSpots
                  .map((s) => LineTooltipItem(
                        '${s.y.round()} dias',
                        const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      ))
                  .toList(),
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= months.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_shortMonth(months[i]),
                        style: const TextStyle(fontSize: 10)),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: MarleyColors.netWorthLine,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                  show: true,
                  color: MarleyColors.spendingPurple.withValues(alpha: 0.12)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fixes fl_chart's default bar tooltip, which colors its text after the
/// touched rod itself (e.g. a translucent purple on the Net Worth chart's
/// unselected bars) on a dark background — nearly unreadable. A plain
/// dark-background/white-text tooltip stays legible regardless of the
/// rod's own color.
BarTouchTooltipData _barTooltipData() {
  return BarTouchTooltipData(
    getTooltipColor: (group) => Colors.black87,
    getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
      formatEur(rod.toY),
      const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
    ),
  );
}

int _asFlex(double value) {
  final v = (value * 1000).round();
  if (v < 1) return 1;
  if (v > 1000000) return 1000000;
  return v;
}

String _shortMonth(String yyyymm) {
  const abbr = [
    '',
    'Jan',
    'Fev',
    'Mar',
    'Abr',
    'Mai',
    'Jun',
    'Jul',
    'Ago',
    'Set',
    'Out',
    'Nov',
    'Dez'
  ];
  final month = int.parse(yyyymm.split('-')[1]);
  return abbr[month];
}
