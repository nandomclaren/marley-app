import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/categories.dart';
import '../state/app_state.dart';
import '../utils/calculations.dart';
import '../utils/formatters.dart';

class MoveMoneySheet extends StatefulWidget {
  final String month;

  const MoveMoneySheet({super.key, required this.month});

  static Future<void> show(BuildContext context, {required String month}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => MoveMoneySheet(month: month),
    );
  }

  @override
  State<MoveMoneySheet> createState() => _MoveMoneySheetState();
}

class _MoveMoneySheetState extends State<MoveMoneySheet> {
  String? _from;
  String? _to;
  final _amountController = TextEditingController();

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final data = appState.data;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Mover dinheiro', style: Theme.of(context).textTheme.titleLarge),
          Text(monthLabel(widget.month),
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _from,
            decoration: const InputDecoration(
                labelText: 'De', border: OutlineInputBorder()),
            items: [
              for (final cat in kAllCategories)
                DropdownMenuItem(
                  value: cat,
                  child: Text(
                      '$cat  (${formatEur(Calculations.availableFor(data, cat, widget.month))})'),
                ),
            ],
            onChanged: (v) => setState(() => _from = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _to,
            decoration: const InputDecoration(
                labelText: 'Para', border: OutlineInputBorder()),
            items: [
              for (final cat in kAllCategories)
                DropdownMenuItem(value: cat, child: Text(cat)),
            ],
            onChanged: (v) => setState(() => _to = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
                labelText: 'Valor (€)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: (_from == null || _to == null || _from == _to)
                ? null
                : () async {
                    final amount = double.tryParse(
                            _amountController.text.replaceAll(',', '.')) ??
                        0;
                    if (amount <= 0) return;
                    await appState.moveMoney(
                      month: widget.month,
                      fromCat: _from!,
                      toCat: _to!,
                      amount: amount,
                    );
                    if (context.mounted) Navigator.of(context).pop();
                  },
            child: const Text('Mover'),
          ),
        ],
      ),
    );
  }
}
