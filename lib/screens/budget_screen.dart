import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/categories.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/calculations.dart';
import '../utils/formatters.dart';
import '../widgets/category_detail_sheet.dart';
import '../widgets/month_picker.dart';
import '../widgets/move_money_sheet.dart';
import '../widgets/summary_cards.dart';
import '../widgets/sync_button.dart';

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  // Categories currently red/yellow "linger" in the Attention group for
  // 300ms after they stop being red/yellow, instead of snapping straight
  // back to their origin group — same delayed-reorder idea as Fluxo's
  // pending/settled split.
  final Set<String> _pendingRemoval = {};
  Set<String> _lastAttentionSet = {};

  void _syncAttentionTransitions(Set<String> current) {
    final leaving = _lastAttentionSet.difference(current);
    for (final cat in leaving) {
      if (_pendingRemoval.contains(cat)) continue;
      _pendingRemoval.add(cat);
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        setState(() => _pendingRemoval.remove(cat));
      });
    }
    // Re-entering Attention before the grace period ends cancels the
    // pending removal — no flicker back down and immediately back up.
    _pendingRemoval.removeWhere(current.contains);
    _lastAttentionSet = current;
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final data = appState.data;
    final month = appState.selectedMonth;
    final brightness = Theme.of(context).brightness;

    var displayedAttention = const <String>{};
    if (appState.attentionGroupEnabled) {
      final current = <String>{
        for (final cat in kAllCategories)
          if (Calculations.budgetStatusFor(data, cat, month) !=
              BudgetCatStatus.ok)
            cat,
      };
      _syncAttentionTransitions(current);
      displayedAttention = current.union(_pendingRemoval);
    } else if (_lastAttentionSet.isNotEmpty || _pendingRemoval.isNotEmpty) {
      // Setting turned off — drop the grouping instantly, no lingering.
      _lastAttentionSet = {};
      _pendingRemoval.clear();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Budget'),
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: 'Mover dinheiro',
            onPressed: () => MoveMoneySheet.show(context, month: month),
          ),
          const SyncButton(),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          MonthPicker(
            months: data.months,
            selected: month,
            onSelect: (m) => appState.selectMonth(m),
            onAddMonth: () => appState.addNextMonth(),
          ),
          SummaryCards(cards: [
            SummaryCardData(
              label: 'A Alocar',
              value: Calculations.toBeBudgeted(data),
              signedColor: true,
            ),
            SummaryCardData(
              label: 'Total Orçado',
              value: Calculations.totalBudgeted(data, month),
            ),
            SummaryCardData(
              label: 'Total Gasto',
              value: Calculations.totalSpent(data, month).abs(),
              redBelowThreshold: double.infinity,
            ),
            SummaryCardData(
              label: 'Total Disponível',
              value: Calculations.totalAvailable(data, month),
              signedColor: true,
            ),
          ]),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Expanded(
                    flex: 3,
                    child: Text('Categoria',
                        style: Theme.of(context).textTheme.labelSmall)),
                Expanded(
                    flex: 2,
                    child: Text('Orçado',
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.labelSmall)),
                Expanded(
                    flex: 2,
                    child: Text('Gasto',
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.labelSmall)),
                Expanded(
                    flex: 2,
                    child: Text('Disponível',
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.labelSmall)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              children: [
                if (displayedAttention.isNotEmpty) ...[
                  Container(
                    color: pendingHighlightBg(brightness),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: Text(
                      '⚠️ Attention!',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: pendingHighlightStripe(brightness),
                          fontSize: 13),
                    ),
                  ),
                  for (final cat in kAllCategories)
                    if (displayedAttention.contains(cat))
                      _CategoryRow(
                        category: cat,
                        month: month,
                        color: colorForCategory(cat),
                      ),
                ],
                for (final group in kCategoryGroups)
                  if (group.cats.any((c) => !displayedAttention.contains(c)))
                    ...[
                    Container(
                      color: group.color.withValues(
                          alpha: brightness == Brightness.dark ? 0.16 : 0.08),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Text(
                        group.group,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: group.color,
                            fontSize: 13),
                      ),
                    ),
                    for (final cat in group.cats)
                      if (!displayedAttention.contains(cat))
                        _CategoryRow(
                          category: cat,
                          month: month,
                          color: group.color,
                        ),
                  ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final String category;
  final String month;
  final Color color;

  const _CategoryRow(
      {required this.category, required this.month, required this.color});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final data = appState.data;
    final brightness = Theme.of(context).brightness;

    final budgeted = data.budgets[month]?[category] ?? 0;
    final spent = Calculations.spentForCategory(data, month, category);
    final available = Calculations.availableFor(data, category, month);
    final status = Calculations.budgetStatusFor(data, category, month);

    final availableColor = switch (status) {
      BudgetCatStatus.overspent => MarleyColors.red(brightness),
      BudgetCatStatus.underfunded => pendingHighlightStripe(brightness),
      BudgetCatStatus.ok =>
        available == 0 ? Colors.grey : MarleyColors.green(brightness),
    };

    return InkWell(
      onTap: () =>
          CategoryDetailSheet.show(context, category: category, month: month),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  Container(
                      width: 8,
                      height: 8,
                      decoration:
                          BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(category,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
            Expanded(
                flex: 2,
                child: Text(formatEur(budgeted), textAlign: TextAlign.right)),
            Expanded(
                flex: 2,
                child: Text(formatEur(spent), textAlign: TextAlign.right)),
            Expanded(
              flex: 2,
              child: Text(
                formatEur(available),
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: availableColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
