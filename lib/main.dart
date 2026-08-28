import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'screens/budget_screen.dart';
import 'screens/contas_screen.dart';
import 'screens/fluxo_screen.dart';
import 'screens/reflect_screen.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'widgets/sync_conflict_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR');
  await initializeDateFormatting('pt_BR');
  runApp(const MarleyApp());
}

class MarleyApp extends StatelessWidget {
  const MarleyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: Consumer<AppState>(
        builder: (context, appState, _) {
          final brightness =
              appState.isDarkMode ? Brightness.dark : Brightness.light;
          return MaterialApp(
            title: 'Marley',
            debugShowCheckedModeBanner: false,
            theme: buildMarleyTheme(Brightness.light),
            darkTheme: buildMarleyTheme(Brightness.dark),
            themeMode: appState.isDarkModeOverridden
                ? (appState.isDarkMode ? ThemeMode.dark : ThemeMode.light)
                : ThemeMode.system,
            builder: (context, child) {
              // When there's no manual override we still want the app to
              // follow Marley's own "dark after 18h" rule rather than the
              // OS setting, so force the brightness via a wrapping Theme.
              if (appState.isDarkModeOverridden) return child!;
              return Theme(data: buildMarleyTheme(brightness), child: child!);
            },
            home: const SyncConflictGate(child: HomeShell()),
          );
        },
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tabIndex = 0;

  static const _screens = [
    FluxoScreen(),
    BudgetScreen(),
    ReflectScreen(),
    ContasScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      context.read<AppState>().pushIfDirty();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: _tabIndex, children: _screens),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'Fluxo'),
          NavigationDestination(
              icon: Icon(Icons.pie_chart_outline),
              selectedIcon: Icon(Icons.pie_chart),
              label: 'Budget'),
          NavigationDestination(
              icon: Icon(Icons.insights_outlined),
              selectedIcon: Icon(Icons.insights),
              label: 'Reflect'),
          NavigationDestination(
              icon: Icon(Icons.account_balance_outlined),
              selectedIcon: Icon(Icons.account_balance),
              label: 'Contas'),
        ],
      ),
    );
  }
}
