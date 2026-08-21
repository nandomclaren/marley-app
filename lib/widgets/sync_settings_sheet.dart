import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

class SyncSettingsSheet extends StatefulWidget {
  const SyncSettingsSheet({super.key});

  @override
  State<SyncSettingsSheet> createState() => _SyncSettingsSheetState();

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const Padding(
        padding: EdgeInsets.only(bottom: 0),
        child: SyncSettingsSheet(),
      ),
    );
  }
}

class _SyncSettingsSheetState extends State<SyncSettingsSheet> {
  final _patController = TextEditingController();
  final _gistIdController = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final appState = context.read<AppState>();
    final pat = await appState.gistSync.getPat();
    final gistId = await appState.gistSync.getGistId();
    if (!mounted) return;
    setState(() {
      _patController.text = pat ?? '';
      _gistIdController.text = gistId ?? '';
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final appState = context.read<AppState>();
    await appState.gistSync.setCredentials(
      pat: _patController.text,
      gistId: _gistIdController.text,
    );
    await appState.trySync();
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _patController.dispose();
    _gistIdController.dispose();
    super.dispose();
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
      child: _loading
          ? const SizedBox(
              height: 120, child: Center(child: CircularProgressIndicator()))
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Sincronização (GitHub Gist)',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'Cole um Personal Access Token com escopo "gist" e o ID do Gist secreto usado para sincronizar os dados.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _patController,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'GitHub Personal Access Token',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _gistIdController,
                  decoration: const InputDecoration(
                      labelText: 'Gist ID', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Salvar e sincronizar'),
                ),
              ],
            ),
    );
  }
}
