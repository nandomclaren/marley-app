import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

/// Wraps the app and, whenever [AppState.pendingConflict] is set, shows a
/// blocking dialog asking the user to pick a side instead of letting either
/// copy silently overwrite the other.
class SyncConflictGate extends StatefulWidget {
  final Widget child;
  const SyncConflictGate({super.key, required this.child});

  @override
  State<SyncConflictGate> createState() => _SyncConflictGateState();
}

class _SyncConflictGateState extends State<SyncConflictGate> {
  bool _dialogOpen = false;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    if (appState.pendingConflict != null && !_dialogOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showConflictDialog();
      });
    }
    return widget.child;
  }

  Future<void> _showConflictDialog() async {
    if (_dialogOpen || !mounted) return;
    final appState = context.read<AppState>();
    final conflict = appState.pendingConflict;
    if (conflict == null) return;

    _dialogOpen = true;
    final fmt = DateFormat('dd/MM HH:mm', 'pt_BR');
    final remoteWhen = fmt.format(
        DateTime.fromMillisecondsSinceEpoch(conflict.remote.lastModified));
    final localWhen = fmt.format(
        DateTime.fromMillisecondsSinceEpoch(conflict.local.lastModified));

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Dados em conflito'),
        content: Text(
          'O servidor tem alterações de outro aparelho feitas depois da última '
          'vez que este sincronizou — e este aparelho também tem mudanças que '
          'ainda não foram enviadas.\n\n'
          'Servidor: $remoteWhen\n'
          'Este aparelho: $localWhen\n\n'
          'Qual versão você quer manter? A outra será substituída.',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await appState.resolveConflictUseRemote();
            },
            child: const Text('Usar do servidor'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await appState.resolveConflictKeepLocal();
            },
            child: const Text('Manter deste aparelho'),
          ),
        ],
      ),
    );
    _dialogOpen = false;
  }
}
