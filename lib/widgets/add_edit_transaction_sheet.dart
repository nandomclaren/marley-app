import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/categories.dart';
import '../models/transaction.dart';
import '../state/app_state.dart';
import '../utils/calculations.dart';
import '../utils/formatters.dart';
import 'category_impact_pill.dart';
import 'category_picker_sheet.dart';

enum _Direction { out, in_ }

class AddEditTransactionSheet extends StatefulWidget {
  final Txn? existing;

  const AddEditTransactionSheet({super.key, this.existing});

  static Future<void> show(BuildContext context, {Txn? existing}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddEditTransactionSheet(existing: existing),
    );
  }

  @override
  State<AddEditTransactionSheet> createState() =>
      _AddEditTransactionSheetState();
}

class _AddEditTransactionSheetState extends State<AddEditTransactionSheet> {
  late DateTime _date;
  late TextEditingController _descController;
  late TextEditingController _amountController;
  late TextEditingController _notesController;
  final FocusNode _descFocus = FocusNode();
  String _acct = kAccounts.first;
  String _cat = '';
  // Tracks the category *we* last auto-filled, so a manual pick that
  // differs from it is never silently overwritten. Mirrors the web app's
  // `lastAutoCat`.
  String? _lastAutoCat;
  List<Txn> _descSuggestions = const [];
  _Direction _direction = _Direction.out;
  bool _recurring = false;
  bool _uncertain = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final t = widget.existing;
    _date = t != null ? parseIso(t.date) : DateTime.now();
    _descController = TextEditingController(text: t?.desc ?? '');
    _notesController = TextEditingController(text: t?.notes ?? '');
    _acct = t?.acct ?? kAccounts.first;
    _cat = t?.cat ?? '';
    _recurring = t?.recurring ?? false;
    _uncertain = t?.warning ?? false;
    if (t != null) {
      _direction = t.out > 0 ? _Direction.out : _Direction.in_;
      final amount = t.out > 0 ? t.out : t.in_;
      _amountController = TextEditingController(
          text: amount == 0 ? '' : amount.toStringAsFixed(2));
    } else {
      _amountController = TextEditingController();
    }
    _descController.addListener(_onDescChanged);
    _descFocus.addListener(() {
      if (!_descFocus.hasFocus) setState(() => _descSuggestions = const []);
    });
  }

  @override
  void dispose() {
    _descController.removeListener(_onDescChanged);
    _descController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    _descFocus.dispose();
    super.dispose();
  }

  /// Live description autocomplete + category memory, ported from the web
  /// app's `updateDescSug()` + `suggestCat()`: as you type, suggest
  /// previously-used descriptions and auto-fill the category from the most
  /// recent matching transaction (never overriding a manual pick).
  void _onDescChanged() {
    final data = context.read<AppState>().data;
    final typed = bareDesc(_descController.text);

    if (typed.length < 3) {
      if (_descSuggestions.isNotEmpty) {
        setState(() => _descSuggestions = const []);
      }
    } else {
      final seen = <String>{};
      final matches = <Txn>[];
      final sorted = [...data.txns]..sort((a, b) => b.date.compareTo(a.date));
      for (final t in sorted) {
        if (t.desc.isEmpty || t.style == 'opening') continue;
        final bare = bareDesc(t.desc);
        if (bare.startsWith(typed) && seen.add(bare)) {
          matches.add(t);
          if (matches.length >= 7) break;
        }
      }
      setState(() => _descSuggestions = matches);
    }

    if (_cat.isNotEmpty && _cat != _lastAutoCat) {
      return; // user chose their own category
    }
    if (typed.length < 2) {
      if (_lastAutoCat != null) setState(() => _cat = '');
      return;
    }
    final best = data.txns
        .where((t) =>
            t.cat.isNotEmpty &&
            t.desc.isNotEmpty &&
            t.style != 'opening' &&
            bareDesc(t.desc).startsWith(typed))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    if (best.isNotEmpty) {
      setState(() {
        _cat = best.first.cat;
        _lastAutoCat = best.first.cat;
      });
    } else if (_lastAutoCat != null) {
      setState(() {
        _cat = '';
        _lastAutoCat = null;
      });
    }
  }

  void _pickSuggestion(Txn t) {
    _descController.text = t.desc;
    _descController.selection = TextSelection.collapsed(offset: t.desc.length);
    setState(() {
      _descSuggestions = const [];
      _cat = t.cat;
      _lastAutoCat = t.cat.isNotEmpty ? t.cat : _lastAutoCat;
    });
    _descFocus.unfocus();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickCategory() async {
    final picked = await CategoryPickerSheet.show(context);
    if (picked != null) setState(() => _cat = picked);
  }

  void _save() {
    final amount =
        double.tryParse(_amountController.text.replaceAll(',', '.')) ?? 0;
    final appState = context.read<AppState>();
    final month = monthOf(toIso(_date));
    // Snapshot before the mutation so the impact pill (below) can show
    // what actually changed. addTxn/updateTxn run synchronously up to
    // their first `await` (the local-storage write), so `appState.data`
    // already reflects the edit by the time control returns here even
    // though neither call is awaited.
    final before =
        _cat.isEmpty ? 0.0 : Calculations.availableFor(appState.data, _cat, month);
    final txn = Txn(
      id: widget.existing?.id ?? appState.nextTxnId(),
      date: toIso(_date),
      desc: _descController.text.trim(),
      acct: _acct,
      out: _direction == _Direction.out ? amount : 0,
      in_: _direction == _Direction.in_ ? amount : 0,
      notes: _notesController.text.trim(),
      style: _uncertain ? 'warning' : (widget.existing?.style ?? 'normal'),
      recurring: _recurring,
      warning: _uncertain,
      cleared: widget.existing?.cleared ?? false,
      locked: widget.existing?.locked ?? false,
      cat: _cat,
      // Editing never changes when/how a txn was added or last settled —
      // those are only ever touched by addTxn/toggleCleared/reconcile.
      addedManually: widget.existing?.addedManually ?? false,
      settledAt: widget.existing?.settledAt,
    );
    if (_isEditing) {
      appState.updateTxn(txn);
    } else {
      appState.addTxn(txn);
    }
    if (_cat.isNotEmpty) {
      final after = Calculations.availableFor(appState.data, _cat, month);
      if ((after - before).abs() > 0.005) {
        CategoryImpactPill.show(context,
            category: _cat, before: before, after: after);
      }
    }
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final appState = context.read<AppState>();
    await appState.deleteTxn(widget.existing!.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isEditing ? 'Editar transação' : 'Nova transação',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (_isEditing)
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: _delete,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Data'),
                trailing: Text(toIso(_date)),
                onTap: _pickDate,
              ),
              TextField(
                controller: _descController,
                focusNode: _descFocus,
                decoration: const InputDecoration(
                    labelText: 'Descrição', border: OutlineInputBorder()),
              ),
              if (_descSuggestions.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final t in _descSuggestions)
                        ListTile(
                          dense: true,
                          title: Text(t.desc),
                          subtitle: t.cat.isNotEmpty ? Text(t.cat) : null,
                          onTap: () => _pickSuggestion(t),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<_Direction>(
                      segments: const [
                        ButtonSegment(
                            value: _Direction.out, label: Text('Saída')),
                        ButtonSegment(
                            value: _Direction.in_, label: Text('Entrada')),
                      ],
                      selected: {_direction},
                      onSelectionChanged: (s) =>
                          setState(() => _direction = s.first),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Valor (€)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _acct,
                decoration: const InputDecoration(
                    labelText: 'Conta', border: OutlineInputBorder()),
                items: [
                  for (final a in kAccounts)
                    DropdownMenuItem(value: a, child: Text(a)),
                  const DropdownMenuItem(
                      value: kNoAccount, child: Text('Sem conta')),
                ],
                onChanged: (v) => setState(() => _acct = v ?? _acct),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Categoria'),
                trailing: Text(
                  _cat.isEmpty ? 'Selecionar' : _cat,
                  style: _cat.isEmpty
                      ? TextStyle(
                          color: Theme.of(context).textTheme.bodySmall?.color)
                      : null,
                ),
                onTap: _pickCategory,
              ),
              TextField(
                controller: _notesController,
                decoration: const InputDecoration(
                    labelText: 'Notas', border: OutlineInputBorder()),
                maxLines: 2,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Recorrente'),
                value: _recurring,
                onChanged: (v) => setState(() => _recurring = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Incerto (valor pode mudar)'),
                value: _uncertain,
                onChanged: (v) => setState(() => _uncertain = v),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _save,
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      ),
    );
  }
}
