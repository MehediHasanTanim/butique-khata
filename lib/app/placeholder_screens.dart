import 'package:flutter/material.dart';
import 'package:tailor_khata/core/ui/empty_state.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

/// Placeholder tab bodies replaced feature by feature in later sprints.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.homeTitle)),
      body: EmptyState(
        icon: Icons.today_outlined,
        title: l10n.appName,
        body: l10n.homePlaceholder,
      ),
    );
  }
}

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.ordersTitle)),
      body: EmptyState(
        icon: Icons.receipt_long_outlined,
        title: l10n.ordersEmptyTitle,
        body: l10n.ordersEmptyBody,
      ),
    );
  }
}

class RushScreen extends StatelessWidget {
  const RushScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.rushTitle)),
      body: EmptyState(
        icon: Icons.local_fire_department_outlined,
        title: l10n.rushEmptyTitle,
        body: l10n.rushEmptyBody,
      ),
    );
  }
}
