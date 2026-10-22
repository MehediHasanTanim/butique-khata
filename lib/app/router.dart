import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:tailor_khata/app/home_shell.dart';
import 'package:tailor_khata/app/placeholder_screens.dart';
import 'package:tailor_khata/app/routes.dart';
import 'package:tailor_khata/features/customers/presentation/customer_form_screen.dart';
import 'package:tailor_khata/features/customers/presentation/customer_list_screen.dart';
import 'package:tailor_khata/features/customers/presentation/customer_picker_screen.dart';
import 'package:tailor_khata/features/customers/presentation/customer_profile_screen.dart';
import 'package:tailor_khata/features/dev/seed_screen.dart';
import 'package:tailor_khata/features/measurements/presentation/measurement_compare_screen.dart';
import 'package:tailor_khata/features/measurements/presentation/measurement_entry_screen.dart';
import 'package:tailor_khata/features/measurements/presentation/measurement_history_screen.dart';
import 'package:tailor_khata/features/measurements/presentation/measurement_trend_screen.dart';
import 'package:tailor_khata/features/orders/presentation/new_order_screen.dart';
import 'package:tailor_khata/features/orders/presentation/order_detail_screen.dart';
import 'package:tailor_khata/features/orders/presentation/orders_screen.dart';
import 'package:tailor_khata/features/settings/presentation/more_screen.dart';

export 'package:tailor_khata/app/routes.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

GoRouter buildRouter({String initialLocation = AppRoutes.home}) => GoRouter(
  navigatorKey: rootNavigatorKey,
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
              builder: (context, state) => const CustomerListScreen(),
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
                  parentNavigatorKey: rootNavigatorKey,
                  builder: (context, state) => const SeedScreen(),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.pickCustomer,
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const CustomerPickerScreen(),
    ),
    GoRoute(
      path: '/order/:id',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) =>
          OrderDetailScreen(orderId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: AppRoutes.customerNew,
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const CustomerFormScreen(),
    ),
    GoRoute(
      path: '/customer/:id',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) =>
          CustomerProfileScreen(customerId: state.pathParameters['id']!),
      routes: [
        GoRoute(
          path: 'edit',
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) =>
              CustomerFormScreen(customerId: state.pathParameters['id']),
        ),
        GoRoute(
          path: 'history/:garment',
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => MeasurementHistoryScreen(
            customerId: state.pathParameters['id']!,
            garmentKey: state.pathParameters['garment']!,
          ),
        ),
        GoRoute(
          path: 'compare/:garment',
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => MeasurementCompareScreen(
            customerId: state.pathParameters['id']!,
            garmentKey: state.pathParameters['garment']!,
            earlierId: state.uri.queryParameters['a'],
            laterId: state.uri.queryParameters['b'],
          ),
        ),
        GoRoute(
          path: 'trend/:garment',
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => MeasurementTrendScreen(
            customerId: state.pathParameters['id']!,
            garmentKey: state.pathParameters['garment']!,
          ),
        ),
        GoRoute(
          path: 'order/new',
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => NewOrderScreen(
            customerId: state.pathParameters['id']!,
            duplicateOf: state.uri.queryParameters['dup'],
          ),
        ),
        GoRoute(
          path: 'measure/:garment',
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => MeasurementEntryScreen(
            customerId: state.pathParameters['id']!,
            garmentKey: state.pathParameters['garment']!,
          ),
        ),
      ],
    ),
  ],
  errorBuilder: (context, state) =>
      const Scaffold(body: Center(child: Icon(Icons.error_outline))),
);
