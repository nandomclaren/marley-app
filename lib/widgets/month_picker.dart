import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/formatters.dart';

class MonthPicker extends StatelessWidget {
  final List<String> months;
  final String selected;
  final ValueChanged<String> onSelect;
  final VoidCallback onAddMonth;

  const MonthPicker({
    super.key,
    required this.months,
    required this.selected,
    required this.onSelect,
    required this.onAddMonth,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final m in months) ...[
            _MonthChip(
              label: '📅 ${monthLabel(m)}',
              selected: m == selected,
              onTap: () => onSelect(m),
            ),
            const SizedBox(width: 8),
          ],
          OutlinedButton(
            onPressed: onAddMonth,
            style: OutlinedButton.styleFrom(
              shape: const StadiumBorder(),
              side:
                  BorderSide(color: MarleyColors.accent.withValues(alpha: 0.4)),
            ),
            child: const Text('+ mês'),
          ),
        ],
      ),
    );
  }
}

class _MonthChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _MonthChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: MarleyColors.accent,
      labelStyle: TextStyle(
        color: selected
            ? Colors.white
            : Theme.of(context).textTheme.bodyMedium?.color,
        fontWeight: FontWeight.w600,
      ),
      shape: const StadiumBorder(),
    );
  }
}
