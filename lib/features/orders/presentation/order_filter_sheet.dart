import 'package:flutter/material.dart';
import 'package:tailor_khata/core/time/clock.dart';
import 'package:tailor_khata/core/time/date_format.dart';
import 'package:tailor_khata/features/measurements/domain/measurement.dart';
import 'package:tailor_khata/features/orders/domain/delivery.dart';
import 'package:tailor_khata/features/orders/domain/order_status.dart';
import 'package:tailor_khata/features/orders/presentation/order_labels.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

/// Pick status, balance, garment and delivery dates to narrow the order list
/// (S-2). Pops with the chosen [OrderFilter].
class OrderFilterSheet extends StatefulWidget {
  const OrderFilterSheet({
    required this.initial,
    required this.garments,
    super.key,
  });

  final OrderFilter initial;
  final List<GarmentInfo> garments;

  @override
  State<OrderFilterSheet> createState() => _OrderFilterSheetState();
}

class _OrderFilterSheetState extends State<OrderFilterSheet> {
  late final Set<OrderStatus> _statuses = {...widget.initial.statuses};
  late bool _dueOnly = widget.initial.dueOnly;
  late String? _garment = widget.initial.garmentTypeId;
  late String? _from = widget.initial.from;
  late String? _to = widget.initial.to;

  Future<String?> _pick(String? current) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current == null ? now : Clock.parseDate(current),
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 3),
    );
    return picked == null ? null : Clock.toDateString(picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final theme = Theme.of(context);

    Widget dateTile(
      String label,
      String? value,
      ValueChanged<String?> onChanged,
      Key key,
    ) => Expanded(
      child: ListTile(
        key: key,
        contentPadding: EdgeInsets.zero,
        title: Text(label, style: theme.textTheme.labelMedium),
        subtitle: Text(
          value == null ? l10n.notSet : formatStoredDate(value, lang),
        ),
        trailing: value == null
            ? const Icon(Icons.event, size: 20)
            : IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => setState(() => onChanged(null)),
              ),
        onTap: () async {
          final d = await _pick(value);
          if (d != null) setState(() => onChanged(d));
        },
      ),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.filterTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Text(l10n.filterStatus, style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                for (final status in OrderStatus.values)
                  FilterChip(
                    key: ValueKey('filter-status-${status.name}'),
                    label: Text(status.label(l10n)),
                    selected: _statuses.contains(status),
                    onSelected: (on) => setState(() {
                      on ? _statuses.add(status) : _statuses.remove(status);
                    }),
                  ),
              ],
            ),
            SwitchListTile(
              key: const ValueKey('filter-due'),
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.filterDueOnly),
              value: _dueOnly,
              onChanged: (v) => setState(() => _dueOnly = v),
            ),
            DropdownButtonFormField<String?>(
              key: const ValueKey('filter-garment'),
              initialValue: _garment,
              decoration: InputDecoration(labelText: l10n.filterGarment),
              items: [
                DropdownMenuItem(
                  value: null,
                  child: Text(l10n.filterAnyGarment),
                ),
                for (final g in widget.garments)
                  DropdownMenuItem(value: g.id, child: Text(g.label(lang))),
              ],
              onChanged: (v) => setState(() => _garment = v),
            ),
            const SizedBox(height: 8),
            Text(l10n.filterDates, style: theme.textTheme.labelLarge),
            Row(
              children: [
                dateTile(
                  l10n.filterFrom,
                  _from,
                  (v) => _from = v,
                  const ValueKey('filter-from'),
                ),
                const SizedBox(width: 12),
                dateTile(
                  l10n.filterTo,
                  _to,
                  (v) => _to = v,
                  const ValueKey('filter-to'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  key: const ValueKey('filter-clear'),
                  onPressed: () => Navigator.pop(
                    context,
                    OrderFilter(query: widget.initial.query),
                  ),
                  child: Text(l10n.filterClear),
                ),
                const Spacer(),
                FilledButton(
                  key: const ValueKey('filter-apply'),
                  onPressed: () => Navigator.pop(
                    context,
                    OrderFilter(
                      query: widget.initial.query,
                      statuses: _statuses,
                      dueOnly: _dueOnly,
                      garmentTypeId: _garment,
                      from: _from,
                      to: _to,
                    ),
                  ),
                  child: Text(l10n.filterApply),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
