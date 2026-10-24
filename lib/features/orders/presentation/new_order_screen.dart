import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/app/routes.dart';
import 'package:tailor_khata/app/services.dart';
import 'package:tailor_khata/core/l10n/digit_formatter.dart';
import 'package:tailor_khata/core/money/money.dart';
import 'package:tailor_khata/core/time/clock.dart';
import 'package:tailor_khata/core/time/date_format.dart';
import 'package:tailor_khata/core/ui/money_text.dart';
import 'package:tailor_khata/core/ui/primary_button.dart';
import 'package:tailor_khata/features/customers/presentation/customer_providers.dart';
import 'package:tailor_khata/features/measurements/domain/measurement.dart';
import 'package:tailor_khata/features/measurements/domain/measurement_format.dart';
import 'package:tailor_khata/features/measurements/presentation/measurement_providers.dart';
import 'package:tailor_khata/features/orders/domain/order.dart';
import 'package:tailor_khata/features/orders/domain/style_catalog.dart';
import 'package:tailor_khata/features/orders/presentation/order_draft.dart';
import 'package:tailor_khata/features/orders/presentation/order_labels.dart';
import 'package:tailor_khata/features/orders/presentation/order_providers.dart';
import 'package:tailor_khata/features/orders/presentation/photo_widgets.dart';
import 'package:tailor_khata/features/rush/presentation/rush_providers.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

/// New-order wizard: garments → measurements → details & price → delivery
/// and payment (O-1…O-5, P-1, H-5). With [duplicateOf] it starts from an
/// earlier order ("same as last Eid", O-13).
class NewOrderScreen extends ConsumerStatefulWidget {
  const NewOrderScreen({required this.customerId, this.duplicateOf, super.key});

  final String customerId;
  final String? duplicateOf;

  @override
  ConsumerState<NewOrderScreen> createState() => _NewOrderScreenState();
}

class _NewOrderScreenState extends ConsumerState<NewOrderScreen> {
  static const _steps = 4;

  OrderDraft? _draft;
  String _customerName = '';
  List<GarmentInfo> _garments = const [];
  int _step = 0;
  bool _saving = false;
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final customer = await ref
        .read(customerRepositoryProvider)
        .byId(widget.customerId);
    final garments = await ref.read(measurementRepositoryProvider).garments();
    if (!mounted || customer == null) return;
    final clock = ref.read(clockProvider);
    final defaultDelivery = Clock.toDateString(
      clock.now().add(const Duration(days: 7)),
    );
    final draft = OrderDraft(
      customerId: customer.id,
      deliveryDate: defaultDelivery,
    );

    final dup = widget.duplicateOf;
    if (dup != null) {
      final source = await ref.read(orderRepositoryProvider).detail(dup);
      if (source != null) {
        draft.urgent = source.order.urgent;
        draft.note = source.order.note ?? '';
        for (final item in source.items) {
          final garment = garments
              .where((g) => g.id == item.garmentTypeId)
              .firstOrNull;
          if (garment == null) continue;
          final copy = DraftItem(garment: garment, qty: item.qty)
            ..style = Map.of(item.style)
            ..fabric = item.fabricSource ?? FabricSource.shop
            ..colour = item.colour ?? ''
            ..note = item.note ?? ''
            ..priceText = item.price.toInputString();
          draft.items.add(copy);
        }
      }
    }
    // Pre-select the latest measurements for every garment (H-5).
    for (final item in draft.items) {
      await _useLatest(draft, item);
    }
    if (!mounted) return;
    setState(() {
      _draft = draft;
      _customerName = customer.name;
      _garments = garments;
    });
  }

  Future<void> _useLatest(OrderDraft draft, DraftItem item) async {
    final latest = await ref
        .read(measurementRepositoryProvider)
        .latest(draft.customerId, item.garment.id);
    item.latest = latest;
    item.measurement = latest;
    item.measurementSetId = latest?.id;
  }

  /// Photos of an order that was never saved are not kept.
  Future<void> _deleteDraftPhotos(OrderDraft draft) async {
    final media = ref.read(mediaStoreProvider);
    for (final item in draft.items) {
      for (final photo in item.photos) {
        await media.delete(photo);
      }
    }
  }

  Future<bool> _confirmFullDate(String seasonName) async {
    final l10n = AppL10n.of(context);
    final take = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.dateFullTitle),
        content: Text(l10n.dateFullBody(seasonName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.actionGoBack),
          ),
          TextButton(
            key: const ValueKey('date-full-take'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.dateFullTake),
          ),
        ],
      ),
    );
    return take ?? false;
  }

  Future<bool> _confirmDiscard() async {
    final l10n = AppL10n.of(context);
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.discardOrderTitle),
        content: Text(l10n.discardOrderBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.actionKeepEditing),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.actionDiscard),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  /// Validation message for the current step, or null when it can proceed.
  String? _validateStep(AppL10n l10n) {
    final draft = _draft!;
    switch (_step) {
      case 0:
        return draft.items.isEmpty ? l10n.needGarment : null;
      case 2:
        return draft.pricesComplete ? null : l10n.priceRequired;
      case 3:
        if (draft.discount == null || draft.advance == null) {
          return l10n.errInvalidAmount;
        }
        if (draft.discount! > draft.subtotal) return l10n.errDiscountTooBig;
        if (draft.advance! > draft.total) return l10n.errAdvanceTooMuch;
        return null;
      default:
        return null;
    }
  }

  Future<void> _next() async {
    final l10n = AppL10n.of(context);
    final problem = _validateStep(l10n);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() => _error = null);
    if (_step < _steps - 1) {
      setState(() => _step++);
      if (_step == _steps - 1) _suggestDeliveryDate();
      return;
    }
    await _save();
  }

  /// With a season set up, start the delivery date at the earliest day the
  /// plan has room for this order (E-5), unless the tailor already chose one.
  void _suggestDeliveryDate() {
    final draft = _draft!;
    final plan = ref.read(rushPlanProvider);
    if (plan == null || draft.deliveryTouched) return;
    final safe = plan.safeDate(draft.workUnits);
    if (safe != null) {
      draft.deliveryDate = safe;
      draft.changed();
    }
  }

  Future<void> _save() async {
    final draft = _draft!;
    final plan = ref.read(rushPlanProvider);
    var overbooked = false;
    if (plan != null && !plan.isSafe(draft.workUnits, draft.deliveryDate)) {
      // One extra tap to take an order for a date that is already full.
      if (!await _confirmFullDate(plan.season.name)) return;
      overbooked = true;
    }
    final order = draft.build(
      paidOn: ref.read(clockProvider).today(),
      seasonId:
          plan != null &&
              draft.deliveryDate.compareTo(plan.season.targetDate) <= 0
          ? plan.season.id
          : null,
      overbooked: overbooked,
    );
    if (order == null) return;
    setState(() => _saving = true);
    final result = await ref.read(createOrderProvider)(order);
    if (!mounted) return;
    setState(() => _saving = false);
    result.when(
      ok: (detail) {
        _done = true;
        context.pushReplacement(AppRoutes.order(detail.order.id));
      },
      err: (failure) => setState(() => _error = failure.code),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Keep the Eid-rush plan loaded while the wizard is open.
    ref.watch(rushPlanProvider);
    final l10n = AppL10n.of(context);
    final bangla = ref.watch(useBanglaDigitsProvider);
    final draft = _draft;
    if (draft == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final titles = [
      l10n.stepGarments,
      l10n.stepMeasurements,
      l10n.stepDetails,
      l10n.stepDelivery,
    ];

    return ListenableBuilder(
      listenable: draft,
      builder: (context, _) => PopScope(
        canPop: _done || draft.items.isEmpty,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final navigator = Navigator.of(context);
          if (await _confirmDiscard()) {
            _done = true;
            await _deleteDraftPhotos(draft);
            navigator.pop();
          }
        },
        child: Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.newOrder,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  _customerName,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(44),
              child: Column(
                children: [
                  LinearProgressIndicator(value: (_step + 1) / _steps),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Text(
                          DigitFormatter.format(
                            l10n.wizardStepOf(_step + 1, _steps),
                            bangla: bangla,
                          ),
                          key: const ValueKey('step-counter'),
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            titles[_step],
                            key: const ValueKey('step-title'),
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          body: Column(
            children: [
              Expanded(
                child: switch (_step) {
                  0 => _GarmentsStep(
                    draft: draft,
                    garments: _garments,
                    onAdd: (g) async {
                      final item = DraftItem(garment: g);
                      await _useLatest(draft, item);
                      draft.addItem(item);
                    },
                  ),
                  1 => _MeasurementsStep(draft: draft),
                  2 => _DetailsStep(draft: draft),
                  _ => _DeliveryStep(draft: draft),
                },
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    _error!,
                    key: const ValueKey('wizard-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      if (_step > 0) ...[
                        OutlinedButton(
                          key: const ValueKey('wizard-back'),
                          onPressed: () => setState(() {
                            _step--;
                            _error = null;
                          }),
                          child: Text(l10n.stepBack),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: PrimaryButton(
                          key: const ValueKey('wizard-next'),
                          label: _step == _steps - 1
                              ? l10n.saveOrder
                              : l10n.stepNext,
                          onPressed: _saving ? null : _next,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- step 1: garments --------------------------------------------------------

class _GarmentsStep extends ConsumerWidget {
  const _GarmentsStep({
    required this.draft,
    required this.garments,
    required this.onAdd,
  });

  final OrderDraft draft;
  final List<GarmentInfo> garments;
  final Future<void> Function(GarmentInfo) onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final bangla = ref.watch(useBanglaDigitsProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final item in draft.items)
          Card(
            key: ObjectKey(item),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.garment.label(lang),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.quantity,
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: item.qty > 1
                        ? () {
                            item.qty--;
                            draft.changed();
                          }
                        : null,
                  ),
                  Text(
                    DigitFormatter.format('${item.qty}', bangla: bangla),
                    key: ValueKey(
                      'qty-${item.garment.key}${draft.keySuffix(item)}',
                    ),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  IconButton(
                    tooltip: l10n.quantity,
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () {
                      item.qty++;
                      draft.changed();
                    },
                  ),
                  IconButton(
                    tooltip: l10n.removeItem,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => draft.removeItem(item),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        Text(l10n.addGarment, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final g in garments)
              ActionChip(
                key: ValueKey('add-${g.key}'),
                avatar: const Icon(Icons.add, size: 18),
                label: Text(g.label(lang)),
                onPressed: () => onAdd(g),
              ),
          ],
        ),
      ],
    );
  }
}

// ---- step 2: measurements ----------------------------------------------------

class _MeasurementsStep extends ConsumerWidget {
  const _MeasurementsStep({required this.draft});

  final OrderDraft draft;

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    DraftItem item,
  ) async {
    final id = await context.push<String>(
      AppRoutes.measure(draft.customerId, item.garment.key),
    );
    if (id == null) return;
    final m = await ref.read(measurementRepositoryProvider).byId(id);
    item
      ..latest = m
      ..measurement = m
      ..measurementSetId = m?.id;
    draft.changed();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final bangla = ref.watch(useBanglaDigitsProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final item in draft.items)
          Card(
            key: ObjectKey(item),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.garment.label(lang),
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  if (item.measurement == null) ...[
                    Text(l10n.noMeasurementsYet),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: ValueKey(
                        'take-${item.garment.key}${draft.keySuffix(item)}',
                      ),
                      onPressed: () => _edit(context, ref, item),
                      icon: const Icon(Icons.straighten),
                      label: Text(l10n.takeNow),
                    ),
                  ] else ...[
                    Text(
                      DigitFormatter.format(
                        '${l10n.measuredOn(formatStoredDate(item.measurement!.takenOn, lang))}'
                        ' · ${l10n.measurementsUsed(item.measurement!.version)}',
                        bangla: bangla,
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final f in item.garment.fields)
                          if (item.measurement!.values.containsKey(f.key))
                            Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text(
                                '${f.label(lang)} '
                                '${formatLength(item.measurement!.values[f.key]!, item.measurement!.unit, bangla: bangla)}',
                              ),
                            ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.hasChanged,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            key: ValueKey(
                              'keep-${item.garment.key}${draft.keySuffix(item)}',
                            ),
                            onPressed: () {
                              item
                                ..measurement = item.latest
                                ..measurementSetId = item.latest?.id;
                              draft.changed();
                            },
                            icon: Icon(
                              item.measurementSetId == item.latest?.id
                                  ? Icons.check_circle
                                  : Icons.check_circle_outline,
                            ),
                            label: Text(l10n.useExisting),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          key: ValueKey(
                            'edit-${item.garment.key}${draft.keySuffix(item)}',
                          ),
                          onPressed: () => _edit(context, ref, item),
                          child: Text(l10n.editMeasurements),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ---- step 3: details & price -------------------------------------------------

class _DetailsStep extends ConsumerWidget {
  const _DetailsStep({required this.draft});

  final OrderDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final item in draft.items)
          Card(
            key: ObjectKey(item),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.qty > 1
                        ? '${item.garment.label(lang)} × ${item.qty}'
                        : item.garment.label(lang),
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  for (final group in StyleCatalog.forGarment(
                    item.garment.key,
                  )) ...[
                    const SizedBox(height: 12),
                    Text(
                      group.label(lang),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final option in group.options)
                          ChoiceChip(
                            key: ValueKey(
                              'style-${item.garment.key}${draft.keySuffix(item)}-${group.key}-${option.key}',
                            ),
                            label: Text(option.label(lang)),
                            selected: item.style[group.key] == option.key,
                            onSelected: (selected) {
                              if (selected) {
                                item.style[group.key] = option.key;
                              } else {
                                item.style.remove(group.key);
                              }
                              draft.changed();
                            },
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  SegmentedButton<FabricSource>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: FabricSource.shop,
                        label: Text(l10n.fabricShop),
                      ),
                      ButtonSegment(
                        value: FabricSource.customer,
                        label: Text(l10n.fabricCustomer),
                      ),
                    ],
                    selected: {item.fabric},
                    onSelectionChanged: (v) {
                      item.fabric = v.first;
                      draft.changed();
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: item.colour,
                    decoration: InputDecoration(labelText: l10n.colourLabel),
                    onChanged: (v) => item.colour = v,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: item.note,
                    decoration: InputDecoration(labelText: l10n.itemNoteLabel),
                    onChanged: (v) => item.note = v,
                  ),
                  const SizedBox(height: 12),
                  DraftPhotosSection(item: item, draft: draft),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: ValueKey(
                      'price-${item.garment.key}${draft.keySuffix(item)}',
                    ),
                    initialValue: item.priceText,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(labelText: l10n.priceLabel),
                    onChanged: (v) {
                      item.priceText = v;
                      draft.changed();
                    },
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ---- step 4: delivery & payment ----------------------------------------------

class _DeliveryStep extends ConsumerWidget {
  const _DeliveryStep({required this.draft});

  final OrderDraft draft;

  Future<String?> _pick(
    BuildContext context,
    WidgetRef ref,
    String initial,
  ) async {
    final now = ref.read(clockProvider).now();
    final picked = await showDatePicker(
      context: context,
      initialDate: Clock.parseDate(initial),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    return picked == null ? null : Clock.toDateString(picked);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final theme = Theme.of(context);

    Widget summaryRow(String label, Widget value, {Key? key}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          KeyedSubtree(key: key, child: value),
        ],
      ),
    );

    final plan = ref.watch(rushPlanProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (plan != null) _SafeDateCard(draft: draft, plan: plan),
        ListTile(
          key: const ValueKey('delivery-date'),
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.deliveryDateLabel),
          subtitle: Text(
            formatStoredDate(draft.deliveryDate, lang),
            style: theme.textTheme.titleMedium,
          ),
          trailing: const Icon(Icons.event),
          onTap: () async {
            final d = await _pick(context, ref, draft.deliveryDate);
            if (d != null) {
              draft.deliveryDate = d;
              draft.deliveryTouched = true;
              draft.changed();
            }
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.trialDateLabel),
          subtitle: Text(
            draft.trialDate == null
                ? l10n.notSet
                : formatStoredDate(draft.trialDate!, lang),
          ),
          trailing: draft.trialDate == null
              ? const Icon(Icons.event)
              : IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    draft.trialDate = null;
                    draft.changed();
                  },
                ),
          onTap: () async {
            final d = await _pick(
              context,
              ref,
              draft.trialDate ?? draft.deliveryDate,
            );
            if (d != null) {
              draft.trialDate = d;
              draft.changed();
            }
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.urgentLabel),
          value: draft.urgent,
          onChanged: (v) {
            draft.urgent = v;
            draft.changed();
          },
        ),
        const Divider(),
        const SizedBox(height: 8),
        TextFormField(
          key: const ValueKey('discount'),
          initialValue: draft.discountText,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: l10n.discountLabel),
          onChanged: (v) {
            draft.discountText = v;
            draft.changed();
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const ValueKey('advance'),
          initialValue: draft.advanceText,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: l10n.advanceLabel),
          onChanged: (v) {
            draft.advanceText = v;
            draft.changed();
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<PayMethod>(
          initialValue: draft.method,
          decoration: InputDecoration(labelText: l10n.paidByLabel),
          items: [
            for (final m in PayMethod.values)
              DropdownMenuItem(value: m, child: Text(m.label(l10n))),
          ],
          onChanged: (m) {
            if (m != null) {
              draft.method = m;
              draft.changed();
            }
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: draft.note,
          decoration: InputDecoration(labelText: l10n.orderNoteLabel),
          onChanged: (v) => draft.note = v,
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                summaryRow(l10n.subtotalLabel, MoneyText(draft.subtotal)),
                summaryRow(
                  l10n.totalLabel,
                  MoneyText(draft.total),
                  key: const ValueKey('summary-total'),
                ),
                summaryRow(
                  l10n.advanceShort,
                  MoneyText(draft.advance ?? Money.zero),
                ),
                const Divider(),
                summaryRow(
                  l10n.dueShort,
                  MoneyText(
                    draft.due,
                    highlightDue: true,
                    style: theme.textTheme.titleLarge,
                  ),
                  key: const ValueKey('summary-due'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The plan's advice for the delivery date of this order (E-5).
class _SafeDateCard extends ConsumerWidget {
  const _SafeDateCard({required this.draft, required this.plan});

  final OrderDraft draft;
  final RushPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final theme = Theme.of(context);
    final bangla = ref.watch(useBanglaDigitsProvider);
    final units = draft.workUnits;
    final safe = plan.safeDate(units);
    final chosenOk = plan.isSafe(units, draft.deliveryDate);
    String d(String s) => DigitFormatter.format(s, bangla: bangla);

    return Card(
      key: const ValueKey('safe-date-card'),
      color: chosenOk
          ? theme.colorScheme.secondaryContainer
          : theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              safe == null
                  ? d(l10n.safeDateNone(plan.season.name))
                  : d(l10n.safeDateTitle(formatStoredDate(safe, lang))),
              key: const ValueKey('safe-date-title'),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              chosenOk ? l10n.safeDateOk : l10n.safeDateFull,
              key: const ValueKey('safe-date-status'),
              style: theme.textTheme.bodyMedium,
            ),
            if (safe != null && safe != draft.deliveryDate)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  key: const ValueKey('safe-date-use'),
                  onPressed: () {
                    draft.deliveryDate = safe;
                    draft.deliveryTouched = true;
                    draft.changed();
                  },
                  child: Text(l10n.safeDateUse),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
