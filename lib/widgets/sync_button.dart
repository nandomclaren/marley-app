import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'sync_settings_sheet.dart';

/// AppBar action: shows sync status and lets the user trigger a manual sync
/// or open credential settings (long-press / when unconfigured).
class SyncButton extends StatelessWidget {
  const SyncButton({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return FutureBuilder<bool>(
      future: appState.gistSync.hasCredentials(),
      builder: (context, snapshot) {
        final configured = snapshot.data ?? true;
        Widget icon;
        if (appState.syncStatus == SyncStatus.syncing) {
          icon = const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        } else if (!configured) {
          icon = const Icon(Icons.cloud_off_outlined);
        } else if (appState.syncStatus == SyncStatus.error) {
          icon = const Icon(Icons.sync_problem_outlined, color: Colors.orange);
        } else {
          icon = const Icon(Icons.cloud_done_outlined);
        }

        return IconButton(
          icon: icon,
          tooltip: configured ? 'Sincronizar' : 'Configurar sincronização',
          onPressed: () async {
            if (!configured) {
              await SyncSettingsSheet.show(context);
            } else {
              await appState.trySync();
              if (appState.syncError != null && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content:
                          Text('Erro ao sincronizar: ${appState.syncError}')),
                );
              }
            }
          },
          onLongPress: () => SyncSettingsSheet.show(context),
        );
      },
    );
  }
}
