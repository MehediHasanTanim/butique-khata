import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/app/routes.dart';
import 'package:tailor_khata/core/l10n/digit_formatter.dart';
import 'package:tailor_khata/core/money/money.dart';
import 'package:tailor_khata/core/time/date_format.dart';
import 'package:tailor_khata/core/ui/empty_state.dart';
import 'package:tailor_khata/core/ui/money_text.dart';
import 'package:tailor_khata/core/ui/primary_button.dart';
import 'package:tailor_khata/features/customers/domain/customer.dart';
import 'package:tailor_khata/features/customers/presentation/customer_providers.dart';
import 'package:tailor_khata/features/measurements/domain/measurement.dart';
import 'package:tailor_khata/features/measurements/presentation/measurement_providers.dart';
import 'package:tailor_khata/features/orders/presentation/order_providers.dart';
import 'package:tailor_khata/features/orders/presentation/order_tile.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

/// Customer header plus tabs: Overview, Measurements, Orders, Payments (C-3).
class CustomerProfileScreen extends ConsumerWidget {
  const CustomerProfileScreen({required this.customerId, super.key});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final customer = ref.watch(customerProvider(customerId));

    return customer.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(l10n.errorGenericTitle)),
      ),
      data: (value) {
        if (value == null) {
          return Scaffold(
            appBar: AppBar(),
            body: EmptyState(
              icon: Icons.person_off_outlined,
              title: l10n.customerNotFound,
              body: '',
            ),
          );
        }
        return DefaultTabController(
          length: 4,
          child: Scaffold(
            appBar: AppBar(
              title: Text(value.name, overflow: TextOverflow.ellipsis),
              actions: [
                IconButton(
                  tooltip: l10n.actionEdit,
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () =>
                      context.push(AppRoutes.customerEdit(value.id)),
                ),
              ],
              bottom: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: l10n.tabOverview),
                  Tab(text: l10n.tabMeasurements),
                  Tab(text: l10n.tabOrders),
                  Tab(text: l10n.tabPayments),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                _OverviewTab(customer: value),
                _MeasurementsTab(customer: value),
                _OrdersTab(customer: value),
                _PaymentsTab(customer: value),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _OverviewTab extends ConsumerWidget {
  const _OverviewTab({required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final bangla = ref.watch(useBanglaDigitsProvider);
    final theme = Theme.of(context);

    Widget row(IconData icon, String label, String? value) => ListTile(
      leading: Icon(icon),
      title: Text(label, style: theme.textTheme.labelMedium),
      subtitle: Text(
        value == null || value.isEmpty ? l10n.detailsNone : value,
        style: theme.textTheme.bodyLarge,
      ),
    );

    final phone = customer.phoneDisplay;
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              CircleAvatar(
                radius: 36,
                child: Text(
                  customer.initial,
                  style: theme.textTheme.headlineMedium,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                customer.name,
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        row(
          Icons.phone_outlined,
          l10n.detailsPhone,
          phone == null ? null : DigitFormatter.format(phone, bangla: bangla),
        ),
        row(Icons.home_outlined, l10n.detailsAddress, customer.address),
        row(Icons.notes_outlined, l10n.detailsNote, customer.note),
      ],
    );
  }
}

class _MeasurementsTab extends ConsumerWidget {
  const _MeasurementsTab({required this.customer});

  final Customer customer;

  Future<void> _pickGarment(BuildContext context, WidgetRef ref) async {
    final l10n = AppL10n.of(context);
    final garments = await ref.read(measurementRepositoryProvider).garments();
    if (!context.mounted) return;
    final lang = Localizations.localeOf(context).languageCode;
    final key = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                l10n.chooseGarment,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final garment in garments)
              ListTile(
                key: ValueKey('garment-${garment.key}'),
                minTileHeight: 56,
                leading: const Icon(Icons.checkroom_outlined),
                title: Text(garment.label(lang)),
                onTap: () => Navigator.pop(context, garment.key),
              ),
          ],
        ),
      ),
    );
    if (key != null && context.mounted) {
      await context.push(AppRoutes.measure(customer.id, key));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final bangla = ref.watch(useBanglaDigitsProvider);
    final latest = ref.watch(latestMeasurementsProvider(customer.id));
    final garments = ref.watch(garmentsProvider).value ?? const <GarmentInfo>[];

    return Column(
      children: [
        Expanded(
          child: latest.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(child: Text(l10n.errorGenericTitle)),
            data: (list) {
              if (list.isEmpty) {
                return EmptyState(
                  icon: Icons.straighten,
                  title: l10n.measurementsEmptyTitle,
                  body: l10n.measurementsEmptyBody,
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: list.length,
                itemBuilder: (context, index) {
                  final m = list[index];
                  final garment = garments
                      .where((g) => g.id == m.garmentTypeId)
                      .firstOrNull;
                  return _MeasurementCard(
                    measurement: m,
                    garment: garment,
                    lang: lang,
                    bangla: bangla,
                    onTap: garment == null
                        ? null
                        : () => context.push(
                            AppRoutes.history(customer.id, garment.key),
                          ),
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: PrimaryButton(
              label: l10n.takeMeasurements,
              icon: Icons.straighten,
              onPressed: () => _pickGarment(context, ref),
            ),
          ),
        ),
      ],
    );
  }
}

class _MeasurementCard extends StatelessWidget {
  const _MeasurementCard({
    required this.measurement,
    required this.garment,
    required this.lang,
    required this.bangla,
    required this.onTap,
  });

  final Measurement measurement;
  final GarmentInfo? garment;
  final String lang;
  final bool bangla;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);
    final fields = garment?.fields ?? const <FieldTemplate>[];
    final shown = fields.where((f) => measurement.values.containsKey(f.key));

    String value(FieldTemplate f) {
      final v = measurement.values[f.key]!;
      return measurement.unit == MeasureUnit.inch
          ? v.toInchFraction(bangla: bangla)
          : v.toCm(bangla: bangla);
    }

    return Card(
      key: ValueKey('measurement-${measurement.garmentTypeId}'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      garment?.label(lang) ?? '',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    DigitFormatter.format(
                      l10n.versionLabel(measurement.version),
                      bangla: bangla,
                    ),
                    style: theme.textTheme.labelMedium,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                l10n.measuredOn(formatStoredDate(measurement.takenOn, lang)),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final f in shown)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text('${f.label(lang)} ${value(f)}'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrdersTab extends ConsumerWidget {
  const _OrdersTab({required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final orders = ref.watch(
      orderSummariesProvider((
        customerId: customer.id,
        openOnly: false,
        filter: null,
      )),
    );
    return Column(
      children: [
        Expanded(
          child: orders.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(child: Text(l10n.errorGenericTitle)),
            data: (list) => list.isEmpty
                ? EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: l10n.ordersEmptyTitle,
                    body: l10n.ordersTabEmpty,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(top: 8),
                    itemCount: list.length,
                    itemBuilder: (context, i) =>
                        OrderTile(summary: list[i], showCustomer: false),
                  ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: PrimaryButton(
              key: const ValueKey('profile-new-order'),
              label: l10n.newOrder,
              icon: Icons.add,
              onPressed: () => context.push(AppRoutes.newOrder(customer.id)),
            ),
          ),
        ),
      ],
    );
  }
}

/// Money owed by this customer, with the orders that still have a balance.
class _PaymentsTab extends ConsumerWidget {
  const _PaymentsTab({required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);
    final due = ref.watch(customerDueProvider(customer.id)).value ?? Money.zero;
    final orders =
        ref
            .watch(
              orderSummariesProvider((
                customerId: customer.id,
                openOnly: false,
                filter: null,
              )),
            )
            .value ??
        const [];
    final owing = orders
        .where((o) => !o.order.isCancelled && o.money.hasDue)
        .toList();
    return ListView(
      padding: const EdgeInsets.only(top: 8),
      children: [
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.customerDueLabel,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                MoneyText(
                  due,
                  key: const ValueKey('customer-due'),
                  highlightDue: true,
                  style: theme.textTheme.headlineSmall,
                ),
              ],
            ),
          ),
        ),
        if (owing.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              l10n.paymentsTabEmpty,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          )
        else
          for (final o in owing) OrderTile(summary: o, showCustomer: false),
      ],
    );
  }
}
