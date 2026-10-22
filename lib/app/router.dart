import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:tailor_khata/app/home_shell.dart';
import 'package:tailor_khata/app/placeholder_screens.dart';
import 'package:tailor_khata/features/dev/seed_screen.dart';
import 'package:tailor_khata/features/settings/presentation/more_screen.dart';

abstract class AppRoutes {
  static const home = '/home';
  static const customers = '/customers';
  static const orders = '/orders';
  static const rush = '/rush';
  static const more = '/more';
  static const seed = '/more/seed';
}

GoRouter buildRouter({String initialLocation = AppRoutes.home}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => HomeShell(shell: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.home,
              builder: (context, state) => const HomeScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.customers,
              builder: (context, state) => const CustomersScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.orders,
              builder: (context, state) => const OrdersScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.rush,
              builder: (context, state) => const RushScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.more,
              builder: (context, state) => const MoreScreen(),
              routes: [
                GoRoute(
                  path: 'seed',
                  builder: (context, state) => const SeedScreen(),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
  errorBuilder: (context, state) =>
      const Scaffold(body: Center(child: Icon(Icons.error_outline))),
);
