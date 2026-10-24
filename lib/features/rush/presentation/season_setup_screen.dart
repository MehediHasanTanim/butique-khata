import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/app/routes.dart';
import 'package:tailor_khata/core/time/clock.dart';
import 'package:tailor_khata/core/time/date_format.dart';
import 'package:tailor_khata/core/ui/primary_button.dart';
import 'package:tailor_khata/core/ui/section_header.dart';
import 'package:tailor_khata/features/customers/presentation/customer_providers.dart';
import 'package:tailor_khata/features/measurements/domain/measurement.dart';
import 'package:tailor_khata/features/measurements/presentation/measurement_providers.dart';
import 'package:tailor_khata/features/rush/domain/season.dart';
import 'package:tailor_khata/features/rush/presentation/rush_labels.dart';
import 'package:tailor_khata/features/rush/presentation/rush_providers.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

/// Create or edit a busy season: kind, deadline, daily capacity, working days
/// and closed dates (E-1, E-4), plus how much work each garment is.
class SeasonSetupScreen extends ConsumerStatefulWidget {
  const SeasonSetupScreen({this.seasonId, super.key});

  final String? seasonId;

  @override
  ConsumerState<SeasonSetupScreen> createState() => _SeasonSetupScreenState();
}

class _SeasonSetupScreenState extends ConsumerState<SeasonSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _capacity = TextEditingController(text: '20');
  final Map<String, TextEditingController> _weights = {};

  SeasonKind _kind = SeasonKind.eidFitr;
  late String _target;
  int _mask = WorkingDays.all;
  final Set<String> _closed = {};
  Season? _existing;
  List<GarmentInfo> _garments = const [];
  bool _loading = true;
  bool _nameEdited = false;

  @override
  void initState() {
    super.initState();
    final clock = ref.read(clockProvider);
    _target = Clock.toDateString(clock.now().add(const Duration(days: 30)));
    _load();
  }

  Future<void> _load() async {
    final garments = await ref.read(measurementRepositoryProvider).garments();
    Season? existing;
    final id = widget.seasonId;
    if (id != null) {
      existing = await ref.read(rushRepositoryProvider).seasonById(id);
    }
    if (!mounted) return;
    setState(() {
      _garments = garments;
      for (final g in garments) {
        _weights[g.id] = TextEditingController(
          text: formatGarments(g.workUnits),
        );
      }
      if (existing == null) {
        _name.text = _kind.label(AppL10n.of(context));
      } else {
        _existing = existing;
        _kind = existing.kind;
        _name.text = existing.name;
        _nameEdited = true;
        _target = existing.targetDate;
        _capacity.text = formatGarments(existing.dailyCapacity);
        _mask = existing.workingDaysMask;
        _closed
          ..clear()
          ..addAll(existing.closedDates);
      }
      _loading = false;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _capacity.dispose();
    for (final c in _weights.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<String?> _pickDate(String initial, {DateTime? first}) async {
    final now = ref.read(clockProvider).now();
    final picked = await showDatePicker(
      context: context,
      initialDate: Clock.parseDate(initial),
      firstDate: first ?? DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    return picked == null ? null : Clock.toDateString(picked);
  }

  /// Back to where the screen was opened from, or the Rush tab if it was
  /// opened directly.
  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.rush);
    }
  }

  Future<void> _save() async {
    final l10n = AppL10n.of(context);
    if (!_formKey.currentState!.validate()) return;
    final capacity = parseGarments(_capacity.text)!;
    final name = _name.text.trim().isEmpty
        ? _kind.label(l10n)
        : _name.text.trim();
    final rush = ref.read(rushRepositoryProvider);

    for (final g in _garments) {
      final units = parseGarments(_weights[g.id]!.text);
      if (units != null && units != g.workUnits) {
        await rush.setGarmentWeight(g.id, units);
      }
    }
    await rush.save(
      Season(
        id: _existing?.id ?? ref.read(idGeneratorProvider).newId(),
        name: name,
        kind: _kind,
        targetDate: _target,
        dailyCapacity: capacity,
        workingDaysMask: _mask,
        closedDates: Set.of(_closed),
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.seasonSaved)));
    _leave();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.seasonSetupTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.seasonSetupTitle)),
      body: Form(
        key: _formKey,
        // A plain column (not a lazy list) so every field is validated even
        // when it is scrolled out of view.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<SeasonKind>(
                key: const ValueKey('season-kind'),
                initialValue: _kind,
                decoration: InputDecoration(labelText: l10n.seasonKind),
                items: [
                  for (final k in SeasonKind.values)
                    DropdownMenuItem(value: k, child: Text(k.label(l10n))),
                ],
                onChanged: (k) => setState(() {
                  _kind = k ?? _kind;
                  if (!_nameEdited) _name.text = _kind.label(l10n);
                }),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('season-name'),
                controller: _name,
                decoration: InputDecoration(labelText: l10n.seasonName),
                onChanged: (_) => _nameEdited = true,
              ),
              ListTile(
                key: const ValueKey('season-target'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.seasonTarget),
                subtitle: Text(
                  formatStoredDate(_target, lang),
                  style: theme.textTheme.titleMedium,
                ),
                trailing: const Icon(Icons.event),
                onTap: () async {
                  final d = await _pickDate(_target);
                  if (d != null) setState(() => _target = d);
                },
              ),
              TextFormField(
                key: const ValueKey('season-capacity'),
                controller: _capacity,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: l10n.seasonCapacity,
                  helperText: l10n.seasonCapacityHelp,
                  helperMaxLines: 2,
                ),
                validator: (v) => parseGarments(v ?? '') == null
                    ? l10n.seasonErrCapacity
                    : null,
              ),
              SectionHeader(l10n.seasonWorkingDays),
              Wrap(
                spacing: 8,
                children: [
                  // Saturday first, as the working week usually starts.
                  for (final weekday in const [6, 7, 1, 2, 3, 4, 5])
                    FilterChip(
                      key: ValueKey('day-$weekday'),
                      label: Text(weekdayLabel(l10n, weekday)),
                      selected: WorkingDays.isWorking(_mask, weekday),
                      onSelected: (_) => setState(
                        () => _mask = WorkingDays.toggle(_mask, weekday),
                      ),
                    ),
                ],
              ),
              SectionHeader(l10n.seasonClosedDates),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final date in (_closed.toList()..sort()))
                    InputChip(
                      key: ValueKey('closed-$date'),
                      label: Text(formatStoredDate(date, lang)),
                      onDeleted: () => setState(() => _closed.remove(date)),
                    ),
                  ActionChip(
                    key: const ValueKey('closed-add'),
                    avatar: const Icon(Icons.add, size: 18),
                    label: Text(l10n.seasonAddClosed),
                    onPressed: () async {
                      final d = await _pickDate(_target);
                      if (d != null) setState(() => _closed.add(d));
                    },
                  ),
                ],
              ),
              SectionHeader(l10n.seasonWeights),
              Text(l10n.seasonWeightsHelp, style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              for (final g in _garments)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(child: Text(g.label(lang))),
                      SizedBox(
                        width: 96,
                        child: TextFormField(
                          key: ValueKey('weight-${g.key}'),
                          controller: _weights[g.id],
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          textAlign: TextAlign.end,
                          validator: (v) => parseGarments(v ?? '') == null
                              ? l10n.seasonErrWeight
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              PrimaryButton(
                key: const ValueKey('season-save'),
                label: l10n.seasonSave,
                onPressed: _save,
              ),
              if (_existing != null)
                TextButton(
                  key: const ValueKey('season-remove'),
                  onPressed: () async {
                    await ref
                        .read(rushRepositoryProvider)
                        .deactivate(_existing!.id);
                    if (context.mounted) _leave();
                  },
                  child: Text(l10n.seasonRemove),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
