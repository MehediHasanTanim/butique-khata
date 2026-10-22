import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/app/routes.dart';
import 'package:tailor_khata/core/l10n/digit_formatter.dart';
import 'package:tailor_khata/core/money/money.dart';
import 'package:tailor_khata/core/ui/app_theme.dart';
import 'package:tailor_khata/core/ui/money_text.dart';
import 'package:tailor_khata/core/ui/section_header.dart';
import 'package:tailor_khata/features/orders/domain/delivery.dart';
import 'package:tailor_khata/features/orders/domain/order.dart';
import 'package:tailor_khata/features/orders/presentation/order_providers.dart';
import 'package:tailor_khata/features/orders/presentation/order_tile.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

/// The first few of today's deliveries, refreshed whenever orders change.
final todayDeliveriesProvider = FutureProvider.autoDispose<List<OrderSummary>>((
  ref,
) {
  // Re-run whenever the counts move (any order change).
  ref.watch(deliveryCountsProvider);
  final today = ref.watch(clockProvider).today();
  return ref
      .watch(orderRepositoryProvider)
      .deliveriesPage(from: today, to: today, limit: 5);
});

/// "What do I need to do today?" at a glance (S-3).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);
    final bangla = ref.watch(useBanglaDigitsProvider);
    final stats = ref.watch(dashboardProvider).value ?? const DashboardStats();
    final counts =
        ref.watch(deliveryCountsProvider).value ?? const DeliveryCounts();
    final today =
        ref.watch(todayDeliveriesProvider).value ?? const <OrderSummary>[];
    String n(int value) => DigitFormatter.format('$value', bangla: bangla);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.homeTitle),
        actions: [
          IconButton(
            key: const ValueKey('home-search'),
            tooltip: l10n.dashSearch,
            icon: const Icon(Icons.search),
            onPressed: () => context.push(AppRoutes.search),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                // Fixed height so Bangla text and large fonts never overflow.
                mainAxisExtent: 152,
              ),
              children: [
                _StatCard(
                  key: const ValueKey('stat-today'),
                  label: l10n.dashDueToday,
                  value: n(stats.dueToday),
                  icon: Icons.today,
                  onTap: () => context.push(AppRoutes.deliveries(tab: 'today')),
                ),
                _StatCard(
                  key: const ValueKey('stat-overdue'),
                  label: l10n.dashOverdue,
                  value: n(stats.overdue),
                  icon: Icons.warning_amber_rounded,
                  highlight: stats.overdue > 0,
                  onTap: () =>
                      context.push(AppRoutes.deliveries(tab: 'overdue')),
                ),
                _StatCard(
                  key: const ValueKey('stat-due'),
                  label: l10n.dashOutstanding,
                  money: stats.totalDue,
                  icon: Icons.account_balance_wallet_outlined,
                  onTap: () => context.go('${AppRoutes.orders}?tab=dues'),
                ),
                _StatCard(
                  key: const ValueKey('stat-received'),
                  label: l10n.dashReceivedToday,
                  value: n(stats.receivedToday),
                  icon: Icons.receipt_long_outlined,
                  onTap: () => context.go(AppRoutes.orders),
                ),
              ],
            ),
          ),
          if (counts.uncollected > 0)
            ListTile(
              key: const ValueKey('stat-uncollected'),
              minTileHeight: kMinTouchTarget,
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text(l10n.dashUncollected),
              trailing: Text(
                n(counts.uncollected),
                style: theme.textTheme.titleMedium,
              ),
              onTap: () =>
                  context.push(AppRoutes.deliveries(tab: 'uncollected')),
            ),
          SectionHeader(
            l10n.dashDueToday,
            trailing: TextButton(
              onPressed: () => context.push(AppRoutes.deliveries(tab: 'today')),
              child: Text(l10n.deliveriesTitle),
            ),
          ),
          if (today.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                l10n.nothingDue,
                key: const ValueKey('home-nothing-due'),
                style: theme.textTheme.bodyMedium,
              ),
            )
          else
            for (final summary in today) OrderTile(summary: summary),
          SectionHeader(l10n.dashQuickActions),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('quick-new-order'),
                    onPressed: () async {
                      final id = await context.push<String>(
                        AppRoutes.pickCustomer,
                      );
                      if (id != null && context.mounted) {
                        await context.push(AppRoutes.newOrder(id));
                      }
                    },
                    icon: const Icon(Icons.add),
                    label: Text(l10n.newOrder),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('quick-new-customer'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(48, kPrimaryButtonHeight),
                    ),
                    onPressed: () => context.push(AppRoutes.customerNew),
                    icon: const Icon(Icons.person_add_alt_1),
                    label: Text(l10n.customerAdd),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.icon,
    required this.onTap,
    this.value,
    this.money,
    this.highlight = false,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final String? value;
  final Money? money;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      color: highlight ? scheme.errorContainer : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: highlight ? scheme.error : scheme.primary),
              // The number takes whatever height is left and shrinks to fit,
              // so Bangla digits and large fonts never overflow the card.
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: money != null
                        ? MoneyText(
                            money!,
                            style: theme.textTheme.headlineSmall,
                          )
                        : Text(
                            value ?? '',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                ),
              ),
              Text(
                label,
                style: theme.textTheme.labelLarge,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
