import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/calculations.dart';
import '../utils/formatters.dart';

enum _Step { ask, enterReal, success }

/// Reconcile flow for one account: shows the app's "cleared balance" and
/// asks whether it matches the real bank balance. "Sim" locks every
/// cleared transaction as-is; "Não" asks for the real value and adds a
/// locked correction transaction for the difference. Matches the web app's
/// `openRecModal` → `recStepYes`/`recSubmitCorrection` flow.
class ReconcileSheet extends StatefulWidget {
  final String acct;
  const ReconcileSheet({super.key, required this.acct});

  static Future<void> show(BuildContext context, {required String acct}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => ReconcileSheet(acct: acct),
    );
  }

  @override
  State<ReconcileSheet> createState() => _ReconcileSheetState();
}

class _ReconcileSheetState extends State<ReconcileSheet> {
  late final double _clearedBal;
  _Step _step = _Step.ask;
  String? _successMessage;
  final _realValController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    _clearedBal =
        Calculations.clearedBalanceForAccount(appState.data, widget.acct);
  }

  @override
  void dispose() {
    _realValController.dispose();
    super.dispose();
  }

  Future<void> _confirmMatches() async {
    final appState = context.read<AppState>();
    await appState.reconcileAccount(
        acct: widget.acct, clearedBalanceBefore: _clearedBal);
    setState(() {
      _step = _Step.success;
      _successMessage =
          'Saldo confirmado: ${formatEur(_clearedBal)}. Transações reconciliadas bloqueadas com 🔒.';
    });
  }

  Future<void> _submitCorrection() async {
    final val = double.tryParse(_realValController.text.replaceAll(',', '.'));
    if (val == null) return;
    final appState = context.read<AppState>();
    await appState.reconcileAccount(
      acct: widget.acct,
      realBalance: val,
      clearedBalanceBefore: _clearedBal,
    );
    final diff = val - _clearedBal;
    setState(() {
      _step = _Step.success;
      _successMessage =
          'Transação de correção de ${formatEur(diff.abs())} adicionada. Transações cleared ocultadas.';
    });
  }

  @override
  Widget build(BuildContext context) {
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
          Text('Reconciliar ${widget.acct}',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          if (_step == _Step.ask) ..._buildAsk(),
          if (_step == _Step.enterReal) ..._buildEnterReal(),
          if (_step == _Step.success) ..._buildSuccess(),
        ],
      ),
    );
  }

  List<Widget> _buildAsk() {
    return [
      Text('Saldo cleared no app',
          style: Theme.of(context).textTheme.bodySmall),
      Text(
        formatEur(_clearedBal),
        style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: MarleyColors.accent),
      ),
      const SizedBox(height: 16),
      const Text('Esse valor bate com o saldo real do banco?'),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => setState(() => _step = _Step.enterReal),
              child: const Text('Não'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
                onPressed: _confirmMatches,
                child: const Text('Sim, confirmar')),
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildEnterReal() {
    return [
      Text(
        'Saldo real do ${widget.acct} (segundo o banco)',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _realValController,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
            labelText: 'Valor (€)', border: OutlineInputBorder()),
        onSubmitted: (_) => _submitCorrection(),
      ),
      const SizedBox(height: 16),
      FilledButton(
          onPressed: _submitCorrection, child: const Text('Salvar correção')),
    ];
  }

  List<Widget> _buildSuccess() {
    return [
      const Text('✨ Reconciliado!',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Text(_successMessage ?? ''),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Fechar'),
      ),
    ];
  }
}
