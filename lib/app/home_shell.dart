import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

/// Bottom-navigation shell: Home, Customers, Orders, Rush, More (Spec §7).
class HomeShell extends StatelessWidget {
  const HomeShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (index) =>
            shell.goBranch(index, initialLocation: index == shell.currentIndex),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.today_outlined),
            selectedIcon: const Icon(Icons.today),
            label: l10n.navHome,
          ),
          NavigationDestination(
            icon: const Icon(Icons.people_outline),
            selectedIcon: const Icon(Icons.people),
            label: l10n.navCustomers,
          ),
          NavigationDestination(
            icon: const Icon(Icons.receipt_long_outlined),
            selectedIcon: const Icon(Icons.receipt_long),
            label: l10n.navOrders,
          ),
          NavigationDestination(
            icon: const Icon(Icons.local_fire_department_outlined),
            selectedIcon: const Icon(Icons.local_fire_department),
            label: l10n.navRush,
          ),
          NavigationDestination(
            icon: const Icon(Icons.more_horiz),
            label: l10n.navMore,
          ),
        ],
      ),
    );
  }
}
