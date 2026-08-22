import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/calculations.dart';
import '../utils/formatters.dart';
import '../widgets/add_edit_transaction_sheet.dart';
import '../widgets/month_picker.dart';
import '../widgets/summary_cards.dart';
import '../widgets/sync_button.dart';
import '../widgets/transaction_tile.dart';

class FluxoScreen extends StatefulWidget {
  const FluxoScreen({super.key});

  @override
  State<FluxoScreen> createState() => _FluxoScreenState();
}

class _FluxoScreenState extends State<FluxoScreen> {
  bool _showFuture = false;
  final _searchController = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final data = appState.data;
    final month = appState.selectedMonth;
    final today = todayIso();
    final currentRealMonth = today.substring(0, 7);

    var monthTxns = data.txns.where((t) => monthOf(t.date) == month).toList();
    if (_search.trim().isNotEmpty) {
      final q = _search.toLowerCase();
      monthTxns =
          monthTxns.where((t) => t.desc.toLowerCase().contains(q)).toList();
    }

    final future = monthTxns.where((t) => t.date.compareTo(today) > 0).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final past = monthTxns.where((t) => t.date.compareTo(today) <= 0).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final ndmp = Calculations.ndmp(data);
    final showNdmp = month == currentRealMonth;
    final summary = Calculations.fluxoSummary(data, month);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fluxo'),
        actions: const [SyncButton(), SizedBox(width: 4)],
      ),
      body: Column(
        children: [
          SummaryCards(cards: [
            SummaryCardData(
              label: 'Início de ${monthLabel(month)}',
              value: summary.startBal,
            ),
            SummaryCardData(
              label: 'Saldo Hoje (${displayDate(today)})',
              value: summary.hojeVal,
            ),
            SummaryCardData(
              label: 'Projetado fim do mês',
              value: summary.finalVal,
            ),
            SummaryCardData(
              label: '⚠️ Mínimo do mês',
              value: summary.minVal ?? 0,
              subtitle: summary.minDate != null
                  ? 'em ${displayDate(summary.minDate!)}'
                  : null,
              dangerCard: true,
              redBelowThreshold: 800,
            ),
          ]),
          MonthPicker(
            months: data.months,
            selected: month,
            onSelect: (m) => appState.selectMonth(m),
            onAddMonth: () => appState.addNextMonth(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar transações...',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _search = '');
                        },
                      ),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                if (future.isNotEmpty) ...[
                  ListTile(
                    dense: true,
                    title: Text(
                      _showFuture
                          ? '▾ PRÓXIMOS — ${future.length} agendados'
                          : '▸ PRÓXIMOS — ${future.length} agendados',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    onTap: () => setState(() => _showFuture = !_showFuture),
                  ),
                  if (_showFuture)
                    for (final t in future)
                      TransactionTile(
                        txn: t,
                        onTap: () =>
                            AddEditTransactionSheet.show(context, existing: t),
                      ),
                  const Divider(height: 1),
                ],
                if (showNdmp) _NdmpRow(value: ndmp),
                for (final t in past)
                  TransactionTile(
                    txn: t,
                    onTap: () =>
                        AddEditTransactionSheet.show(context, existing: t),
                  ),
                if (past.isEmpty && future.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('Nenhuma transação neste mês.')),
                  ),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => AddEditTransactionSheet.show(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _NdmpRow extends StatelessWidget {
  final double value;
  const _NdmpRow({required this.value});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final color = value < 0
        ? MarleyColors.red(brightness)
        : MarleyColors.green(brightness);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('NDMP', style: TextStyle(fontWeight: FontWeight.w700)),
          Text(
            formatEurSigned(value),
            style: TextStyle(fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}
