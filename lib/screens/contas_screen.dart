import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/categories.dart';
import '../state/app_state.dart';
import '../utils/calculations.dart';
import '../utils/formatters.dart';
import '../widgets/add_edit_transaction_sheet.dart';
import '../widgets/reconcile_sheet.dart';
import '../widgets/summary_cards.dart';
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

    var running = Calculations.openingBalanceForAccount(data.balances, _acct);
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

    // "Saldo atual" used to be the ledger's running total including every
    // future-dated and never-cleared transaction — nothing like what the
    // bank actually shows, and nowhere near the reconcile flow's number
    // (which is opening + only what's cleared/locked up to today). Web's
    // Contas header never shows that raw running total either: it shows
    // these three instead, so the reconcile flow's number now always
    // matches one of the cards on screen.
    final workingBal =
        Calculations.workingBalanceForAccount(data, _acct, asOf: today);
    final clearedBal =
        Calculations.clearedBalanceForAccount(data, _acct, asOf: today);
    final unclearedNet =
        Calculations.unclearedNetForAccount(data, _acct, asOf: today);

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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: StatCard(
                      data: SummaryCardData(
                        label: 'Working Balance',
                        value: workingBal,
                        signedColor: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Cleared and Uncleared share one card slot — swipe to
                  // flip between them — instead of Uncleared getting its
                  // own row stretched across the full width.
                  Expanded(
                    child: SwipeableStatCard(pages: [
                      SummaryCardData(label: 'Cleared', value: clearedBal),
                      SummaryCardData(
                        label: 'Uncleared',
                        value: unclearedNet,
                        signedColor: true,
                      ),
                    ]),
                  ),
                ],
              ),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => ReconcileSheet.show(context, acct: _acct),
        icon: const Icon(Icons.balance),
        label: const Text('Reconciliar'),
      ),
    );
  }
}
