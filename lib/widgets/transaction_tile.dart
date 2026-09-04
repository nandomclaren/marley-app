import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/categories.dart';
import '../models/transaction.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

class TransactionTile extends StatelessWidget {
  final Txn txn;
  final VoidCallback? onTap;
  final bool showRunningBalance;
  final double? runningBalance;

  /// Tints the row when it's neither cleared nor locked — Fluxo's past/today
  /// list turns this on so what still needs action stands out; other
  /// screens (Contas, future-scheduled rows) leave it off.
  final bool highlightPending;

  const TransactionTile({
    super.key,
    required this.txn,
    this.onTap,
    this.showRunningBalance = false,
    this.runningBalance,
    this.highlightPending = false,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final showPending = highlightPending && !txn.cleared && !txn.locked;
    final rowColor = showPending
        ? pendingHighlightBg(brightness)
        : rowColorForStyle(txn.style, brightness);
    final net = txn.net;
    final valueColor =
        net < 0 ? MarleyColors.red(brightness) : MarleyColors.green(brightness);

    final row = Material(
      color: rowColor ?? Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: showPending
              ? BoxDecoration(
                  border: Border(
                    left: BorderSide(
                        color: pendingHighlightStripe(brightness), width: 3),
                  ),
                )
              : null,
          child: Padding(
            padding: EdgeInsets.fromLTRB(showPending ? 13 : 16, 10, 16, 10),
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Text(
                    displayDate(txn.date),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              txn.desc,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (txn.recurring)
                            const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: Icon(Icons.repeat,
                                  size: 14, color: Colors.grey),
                            ),
                          if (txn.warning)
                            const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: Icon(Icons.warning_amber_rounded,
                                  size: 14, color: Colors.orange),
                            ),
                          if (txn.locked)
                            const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: Icon(Icons.lock_outline,
                                  size: 14, color: Colors.grey),
                            )
                          else if (txn.cleared)
                            const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: Icon(Icons.copyright,
                                  size: 14, color: Colors.grey),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (txn.cat.isNotEmpty)
                            Flexible(
                              child: Text(
                                txn.cat,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: colorForCategory(txn.cat),
                                    ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          if (txn.cat.isNotEmpty && txn.acct != kNoAccount)
                            const Text('  ·  '),
                          if (txn.acct != kNoAccount)
                            Text(txn.acct,
                                style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatEurSigned(net),
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: valueColor),
                    ),
                    if (showRunningBalance && runningBalance != null)
                      Text(
                        formatEur(runningBalance!),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Locked (already reconciled) rows are immutable — no swipe action.
    if (txn.locked) return row;

    return Dismissible(
      key: ValueKey('txn-clear-${txn.id}'),
      direction: DismissDirection.endToStart,
      background: _ClearSwipeBackground(cleared: txn.cleared),
      confirmDismiss: (_) async {
        final appState = context.read<AppState>();
        if (highlightPending) {
          // This row lives in a list that reorders on state change (Fluxo's
          // attention hierarchy) — apply the toggle after the swipe's
          // snap-back settles, instead of yanking the row out from under
          // the user's finger the instant they lift it.
          unawaited(Future.delayed(const Duration(milliseconds: 400), () {
            appState.toggleCleared(txn.id);
          }));
        } else {
          await appState.toggleCleared(txn.id);
        }
        return false; // never actually remove the row, just snap back
      },
      child: row,
    );
  }
}

class _ClearSwipeBackground extends StatelessWidget {
  final bool cleared;
  const _ClearSwipeBackground({required this.cleared});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final color = cleared ? Colors.grey : MarleyColors.green(brightness);
    return Container(
      color: color.withValues(alpha: 0.18),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            cleared ? 'Desmarcar' : 'Cleared',
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 8),
          Icon(cleared ? Icons.remove_done : Icons.done, color: color),
        ],
      ),
    );
  }
}
