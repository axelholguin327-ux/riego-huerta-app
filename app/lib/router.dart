// Navegación de la app (ver design/diagramas/mapa_navegacion.png).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'state/providers.dart';
import 'theme.dart';
import 'ui/alarmas_screen.dart';
import 'ui/historial_screen.dart';
import 'ui/login_screen.dart';
import 'ui/mas_screens.dart';
import 'ui/panel_screen.dart';
import 'ui/riego_screen.dart';

/// Avisa al router cuando cambia la sesión para redirigir (login ↔ panel).
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(Ref ref) {
    ref.listen(authProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthListenable(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/panel',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final loc = state.matchedLocation;
      if (auth.isLoading && !auth.hasValue) return loc == '/cargando' ? null : '/cargando';
      final logged = auth.value != null;
      if (!logged) return loc == '/login' ? null : '/login';
      if (loc == '/login' || loc == '/cargando') return '/panel';
      return null;
    },
    routes: [
      GoRoute(
          path: '/cargando',
          builder: (_, _) => const Scaffold(body: Center(child: CircularProgressIndicator()))),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _Shell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/panel', builder: (_, _) => const PanelScreen(), routes: [
              GoRoute(
                  path: 'zona/:z',
                  builder: (_, s) => ZoneScreen(zone: int.tryParse(s.pathParameters['z'] ?? '') == 2 ? 2 : 1)),
            ]),
          ]),
          StatefulShellBranch(routes: [GoRoute(path: '/riego', builder: (_, _) => const RiegoScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/alarmas', builder: (_, _) => const AlarmasScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/historial', builder: (_, _) => const HistorialScreen())]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/mas', builder: (_, _) => const MasScreen(), routes: [
              GoRoute(path: 'dispositivo', builder: (_, _) => const DispositivoScreen()),
              GoRoute(path: 'rfid', builder: (_, _) => const RfidScreen(), routes: [
                GoRoute(path: 'nueva', builder: (_, _) => const RfidNuevaScreen()),
              ]),
            ]),
          ]),
        ],
      ),
    ],
  );
});

/// Barra de navegación inferior con 5 pestañas.
class _Shell extends ConsumerWidget {
  final StatefulNavigationShell shell;
  const _Shell({required this.shell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alarms = ref.watch(activeAlarmsProvider).length;
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          const NavigationDestination(
              icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view_rounded), label: 'Panel'),
          const NavigationDestination(
              icon: Icon(Icons.water_drop_outlined), selectedIcon: Icon(Icons.water_drop_rounded), label: 'Riego'),
          NavigationDestination(
            icon: Badge(isLabelVisible: alarms > 0, label: Text('$alarms'), child: const Icon(Icons.notifications_outlined)),
            selectedIcon: const Icon(Icons.notifications_rounded, color: AppColors.verde),
            label: 'Alarmas',
          ),
          const NavigationDestination(
              icon: Icon(Icons.show_chart_rounded), selectedIcon: Icon(Icons.insights_rounded), label: 'Historial'),
          const NavigationDestination(
              icon: Icon(Icons.more_horiz_rounded), selectedIcon: Icon(Icons.more_horiz_rounded), label: 'Más'),
        ],
      ),
    );
  }
}
