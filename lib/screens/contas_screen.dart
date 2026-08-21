import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/categories.dart';
import '../models/app_data.dart';
import '../state/app_state.dart';
import '../utils/formatters.dart';
import '../widgets/add_edit_transaction_sheet.dart';
import '../widgets/sync_button.dart';
import '../widgets/transaction_tile.dart';

class ContasScreen extends StatefulWidget {
  const ContasScreen({super.key});

  @override
  State<ContasScreen> createState() => _ContasScreenState();
}

class _ContasScreenState extends State<ContasScreen> {
  String _acct = kAccounts.first;
  bool _showFuture = true;

  double _openingBalance(Balances b, String acct) {
    switch (acct) {
      case 'Revolut':
        return b.rev;
      case 'Wise':
        return b.wise;
      case 'Swile':
        return b.swile;
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final data = appState.data;
    final today = todayIso();

    final acctTxns = data.txns.where((t) => t.acct == _acct).toList()
      ..sort((a, b) {
        final c = a.date.compareTo(b.date);
        if (c != 0) return c;
        return a.id.compareTo(b.id);
      });

    var running = _openingBalance(data.balances, _acct);
    final balanceAfter = <int, double>{};
    for (final t in acctTxns) {
      if (t.style != 'opening') running += t.net;
      balanceAfter[t.id] = running;
    }

    var visible = acctTxns;
    if (!_showFuture) {
      visible = visible.where((t) => t.date.compareTo(today) <= 0).toList();
    }
    final displayList = visible.reversed.toList();
    final currentBalance = acctTxns.isEmpty
        ? _openingBalance(data.balances, _acct)
        : balanceAfter[acctTxns.last.id]!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contas'),
        actions: const [SyncButton(), SizedBox(width: 4)],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<String>(
              segments: [
                for (final a in kAccounts)
                  ButtonSegment(value: a, label: Text(a))
              ],
              selected: {_acct},
              onSelectionChanged: (s) => setState(() => _acct = s.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Saldo atual',
                    style: Theme.of(context).textTheme.bodyMedium),
                Text(
                  formatEur(currentBalance),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 18),
                ),
              ],
            ),
          ),
          SwitchListTile(
            dense: true,
            title: const Text('Mostrar próximos'),
            value: _showFuture,
            onChanged: (v) => setState(() => _showFuture = v),
          ),
          const Divider(height: 1),
          Expanded(
            child: displayList.isEmpty
                ? const Center(child: Text('Nenhuma transação nesta conta.'))
                : ListView.builder(
                    itemCount: displayList.length,
                    itemBuilder: (context, i) {
                      final t = displayList[i];
                      return TransactionTile(
                        txn: t,
                        showRunningBalance: true,
                        runningBalance: balanceAfter[t.id],
                        onTap: () =>
                            AddEditTransactionSheet.show(context, existing: t),
                      );
                    },
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
