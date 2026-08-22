import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/categories.dart';
import '../models/goal.dart';
import '../models/transaction.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/calculations.dart';
import '../utils/formatters.dart';
import 'add_edit_transaction_sheet.dart';

class CategoryDetailSheet extends StatefulWidget {
  final String category;
  final String month;

  const CategoryDetailSheet(
      {super.key, required this.category, required this.month});

  static Future<void> show(BuildContext context,
      {required String category, required String month}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => CategoryDetailSheet(category: category, month: month),
    );
  }

  @override
  State<CategoryDetailSheet> createState() => _CategoryDetailSheetState();
}

class _CategoryDetailSheetState extends State<CategoryDetailSheet> {
  late TextEditingController _budgetController;
  bool _showFuture = false;

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    final current = appState.data.budgets[widget.month]?[widget.category] ?? 0;
    _budgetController = TextEditingController(
        text: current == 0 ? '' : current.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _budgetController.dispose();
    super.dispose();
  }

  void _saveBudget() {
    final value =
        double.tryParse(_budgetController.text.replaceAll(',', '.')) ?? 0;
    context.read<AppState>().setBudget(widget.month, widget.category, value);
    FocusScope.of(context).unfocus();
  }

  Future<void> _editGoal() async {
    final appState = context.read<AppState>();
    final existing = appState.data.goals[widget.category];
    final result = await showDialog<Goal?>(
      context: context,
      builder: (_) =>
          _GoalEditDialog(category: widget.category, existing: existing),
    );
    if (result == null) return;
    if (result.target == 0) {
      await appState.deleteGoal(widget.category);
    } else {
      await appState.setGoal(widget.category, result);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final data = appState.data;
    final brightness = Theme.of(context).brightness;
    final spent =
        Calculations.spentForCategory(data, widget.month, widget.category);
    final available =
        Calculations.availableFor(data, widget.category, widget.month);
    final carry =
        Calculations.carryoverFor(data, widget.category, widget.month);
    final goal = data.goals[widget.category];

    final today = todayIso();
    final allMonthTxns = data.txns.where(
        (t) => t.cat == widget.category && monthOf(t.date) == widget.month);
    final futureTxns = allMonthTxns
        .where((t) => t.date.compareTo(today) > 0)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final pastTxns = allMonthTxns
        .where((t) => t.date.compareTo(today) <= 0)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Row(
              children: [
                Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                        color: colorForCategory(widget.category),
                        shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(widget.category,
                        style: Theme.of(context).textTheme.titleLarge)),
              ],
            ),
            Text(monthLabel(widget.month),
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            TextField(
              controller: _budgetController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Orçado (€)', border: OutlineInputBorder()),
              onSubmitted: (_) => _saveBudget(),
              onEditingComplete: _saveBudget,
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
                onPressed: _saveBudget, child: const Text('Salvar orçamento')),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _stat(context, 'Carry-over', carry),
                _stat(context, 'Gasto', spent),
                _stat(context, 'Disponível', available,
                    colored: true, brightness: brightness),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Meta', style: Theme.of(context).textTheme.titleMedium),
                TextButton(
                    onPressed: _editGoal,
                    child: Text(goal == null ? 'Definir meta' : 'Editar meta')),
              ],
            ),
            if (goal != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  goal.type == 'monthly'
                      ? 'Meta mensal: ${formatEur(goal.target)}'
                      : 'Meta: ${formatEur(goal.target)} até ${goal.targetDate ?? '-'} '
                          '(contribuição mensal: ${formatEur(goal.monthlyContrib ?? 0)})',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 20),
            Text('Transações do mês',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (futureTxns.isNotEmpty) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  _showFuture
                      ? '▾ PRÓXIMOS — ${futureTxns.length} agendados'
                      : '▸ PRÓXIMOS — ${futureTxns.length} agendados',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
                onTap: () => setState(() => _showFuture = !_showFuture),
              ),
              if (_showFuture)
                for (final t in futureTxns) _txnTile(context, t, brightness),
              const Divider(height: 1),
            ],
            if (pastTxns.isEmpty && futureTxns.isEmpty)
              const Text('Nenhuma transação.'),
            for (final t in pastTxns) _txnTile(context, t, brightness),
          ],
        );
      },
    );
  }

  Widget _txnTile(BuildContext context, Txn t, Brightness brightness) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(t.desc),
      subtitle: Text(displayDate(t.date)),
      trailing: Text(
        formatEurSigned(t.net),
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: t.net < 0
              ? MarleyColors.red(brightness)
              : MarleyColors.green(brightness),
        ),
      ),
      onTap: () async {
        Navigator.of(context).pop();
        await AddEditTransactionSheet.show(context, existing: t);
      },
    );
  }

  Widget _stat(BuildContext context, String label, double value,
      {bool colored = false, Brightness? brightness}) {
    final color = colored
        ? (value < 0
            ? MarleyColors.red(brightness ?? Brightness.light)
            : MarleyColors.green(brightness ?? Brightness.light))
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(formatEur(value),
            style: TextStyle(fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}

class _GoalEditDialog extends StatefulWidget {
  final String category;
  final Goal? existing;

  const _GoalEditDialog({required this.category, this.existing});

  @override
  State<_GoalEditDialog> createState() => _GoalEditDialogState();
}

class _GoalEditDialogState extends State<_GoalEditDialog> {
  String _type = 'monthly';
  late TextEditingController _targetController;
  late TextEditingController _monthlyController;
  DateTime? _targetDate;

  @override
  void initState() {
    super.initState();
    final g = widget.existing;
    _type = g?.type ?? 'monthly';
    _targetController = TextEditingController(
        text: g != null && g.target != 0 ? g.target.toStringAsFixed(2) : '');
    _monthlyController = TextEditingController(
      text: g?.monthlyContrib != null && g!.monthlyContrib != 0
          ? g.monthlyContrib!.toStringAsFixed(2)
          : '',
    );
    _targetDate = g?.targetDate != null ? parseIso(g!.targetDate!) : null;
  }

  @override
  void dispose() {
    _targetController.dispose();
    _monthlyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Meta — ${widget.category}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'monthly', label: Text('Mensal')),
              ButtonSegment(value: 'target_date', label: Text('Data alvo')),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _targetController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Valor alvo (€)'),
          ),
          if (_type == 'target_date') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _monthlyController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'Contribuição mensal (€)'),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Data alvo'),
              trailing: Text(
                  _targetDate != null ? toIso(_targetDate!) : 'Selecionar'),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _targetDate ?? DateTime.now(),
                  firstDate: DateTime.now(),
                  lastDate: DateTime(2100),
                );
                if (picked != null) setState(() => _targetDate = picked);
              },
            ),
          ],
        ],
      ),
      actions: [
        if (widget.existing != null)
          TextButton(
            onPressed: () => Navigator.of(context)
                .pop(const Goal(type: 'monthly', target: 0)),
            child: const Text('Remover'),
          ),
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final target =
                double.tryParse(_targetController.text.replaceAll(',', '.')) ??
                    0;
            final monthly =
                double.tryParse(_monthlyController.text.replaceAll(',', '.')) ??
                    0;
            Navigator.of(context).pop(Goal(
              type: _type,
              target: target,
              targetDate: _type == 'target_date' && _targetDate != null
                  ? toIso(_targetDate!)
                  : null,
              monthlyContrib: _type == 'target_date' ? monthly : null,
            ));
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
