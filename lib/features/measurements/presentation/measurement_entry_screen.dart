import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/core/time/clock.dart';
import 'package:tailor_khata/core/time/date_format.dart';
import 'package:tailor_khata/core/ui/text_input_dialog.dart';
import 'package:tailor_khata/core/units/length.dart';
import 'package:tailor_khata/features/customers/presentation/customer_providers.dart';
import 'package:tailor_khata/features/measurements/domain/measurement.dart';
import 'package:tailor_khata/features/measurements/domain/measurement_diff.dart';
import 'package:tailor_khata/features/measurements/domain/measurement_format.dart';
import 'package:tailor_khata/features/measurements/domain/save_measurement.dart';
import 'package:tailor_khata/features/measurements/presentation/measurement_form_model.dart';
import 'package:tailor_khata/features/measurements/presentation/measurement_keypad.dart';
import 'package:tailor_khata/features/measurements/presentation/measurement_providers.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

/// Take measurements for one garment using the template fields and the
/// custom keypad (M-1, M-2, M-5, §4.4). Starts from the latest version when
/// one exists and always saves a *new* version.
class MeasurementEntryScreen extends ConsumerStatefulWidget {
  const MeasurementEntryScreen({
    required this.customerId,
    required this.garmentKey,
    super.key,
  });

  final String customerId;
  final String garmentKey;

  @override
  ConsumerState<MeasurementEntryScreen> createState() =>
      _MeasurementEntryScreenState();
}

class _MeasurementEntryScreenState
    extends ConsumerState<MeasurementEntryScreen> {
  MeasurementFormModel? _model;
  GarmentInfo? _garment;
  Measurement? _previous;
  String _customerName = '';
  late String _takenOn;
  String _note = '';
  bool _saving = false;
  bool _saved = false;
  bool _missing = false;
  final Map<int, GlobalKey> _rowKeys = {};

  @override
  void initState() {
    super.initState();
    _takenOn = ref.read(clockProvider).today();
    _load();
  }

  Future<void> _load() async {
    final measurements = ref.read(measurementRepositoryProvider);
    final customer = await ref
        .read(customerRepositoryProvider)
        .byId(widget.customerId);
    final garment = (await measurements.garments())
        .where((g) => g.key == widget.garmentKey)
        .firstOrNull;
    if (!mounted) return;
    if (customer == null || garment == null) {
      setState(() => _missing = true);
      return;
    }
    final previous = await measurements.latest(customer.id, garment.id);
    if (!mounted) return;
    final model = MeasurementFormModel(
      fields: garment.fields,
      unit: previous?.unit ?? MeasureUnit.inch,
      initial: previous?.values ?? const {},
    )..addListener(_onModelChanged);
    setState(() {
      _customerName = customer.name;
      _garment = garment;
      _previous = previous;
      _model = model;
    });
  }

  int _lastFocused = 0;

  void _onModelChanged() {
    final model = _model!;
    if (model.focusedIndex != _lastFocused) {
      _lastFocused = model.focusedIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = _rowKeys[_lastFocused]?.currentContext;
        if (context != null && context.mounted) {
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 150),
            alignment: 0.3,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _model?.removeListener(_onModelChanged);
    _model?.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppL10n.of(context);
    final model = _model!;
    final values = model.toValues();
    if (values.isEmpty) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(l10n.enterAtLeastOne),
            // Sit above the keypad so it never blocks typing.
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 310),
          ),
        );
      return;
    }
    if (!await _confirmLargeChanges(values)) return;
    if (!mounted) return;
    setState(() => _saving = true);
    final outcome = await ref
        .read(saveMeasurementProvider)
        .call(
          NewMeasurement(
            customerId: widget.customerId,
            garmentTypeId: _garment!.id,
            takenOn: _takenOn,
            unit: model.unit,
            values: values,
            note: _note.trim().isEmpty ? null : _note.trim(),
            supersedesId: _previous?.id,
          ),
        );
    if (!mounted) return;
    _saved = true;
    final message = switch (outcome) {
      MeasurementSaved() => l10n.measurementSaved,
      MeasurementUnchanged() => l10n.noChangeSaved,
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
    // Callers such as the order wizard get the id of the version to use.
    context.pop(switch (outcome) {
      MeasurementSaved(:final measurement) => measurement.id,
      MeasurementUnchanged(:final latest) => latest.id,
    });
  }

  /// Asks the tailor to confirm fields that moved a lot since last time
  /// (§4.4). Returns true when it is fine to save.
  Future<bool> _confirmLargeChanges(Map<String, Length> values) async {
    final previous = _previous;
    if (previous == null) return true;
    final big = largeChanges(previous.values, values);
    if (big.isEmpty) return true;

    final l10n = AppL10n.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final bangla = ref.read(useBanglaDigitsProvider);
    final unit = _model!.unit;
    final labels = {for (final f in _garment!.fields) f.key: f.label(lang)};
    final lines = [
      for (final d in big)
        l10n.changeConfirmLine(
          labels[d.key] ?? d.key,
          formatLength(d.before!, unit, bangla: bangla),
          formatLength(d.after!, unit, bangla: bangla),
          formatDelta(d.delta!, unit, bangla: bangla),
        ),
    ];
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.changeConfirmTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.changeConfirmBody),
            const SizedBox(height: 12),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  line,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.actionGoBack),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.actionYesSave),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<bool> _confirmDiscard() async {
    final l10n = AppL10n.of(context);
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.discardTitle),
        content: Text(l10n.discardBody),
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

  Future<void> _pickDate() async {
    final now = ref.read(clockProvider).now();
    final current = Clock.parseDate(_takenOn);
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(now.year - 30),
      lastDate: now,
    );
    if (picked != null) setState(() => _takenOn = Clock.toDateString(picked));
  }

  Future<void> _editNote() async {
    final l10n = AppL10n.of(context);
    final result = await TextInputDialog.show(
      context,
      title: l10n.noteLabel,
      confirmLabel: l10n.actionOk,
      cancelLabel: l10n.actionCancel,
      initialText: _note,
      hint: l10n.noteHint,
    );
    if (result != null) setState(() => _note = result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final bangla = ref.watch(useBanglaDigitsProvider);
    final model = _model;
    final garment = _garment;

    if (_missing) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(l10n.customerNotFound)),
      );
    }
    if (model == null || garment == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        return PopScope(
          canPop: _saved || !model.hasValues,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            final navigator = Navigator.of(context);
            if (await _confirmDiscard()) {
              _saved = true;
              navigator.pop();
            }
          },
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            appBar: AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.measureTitle(garment.label(lang)),
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    _customerName,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: _saving ? null : _save,
                  child: Text(l10n.saveMeasurements),
                ),
              ],
            ),
            body: Column(
              children: [
                _TopControls(
                  model: model,
                  takenOnText: formatStoredDate(_takenOn, lang),
                  hasNote: _note.trim().isNotEmpty,
                  onPickDate: _pickDate,
                  onEditNote: _editNote,
                ),
                if (_previous != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        l10n.prefilledFromLast(
                          formatStoredDate(_previous!.takenOn, lang),
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: model.fields.length,
                    itemBuilder: (context, index) => _FieldRow(
                      key: _rowKeys.putIfAbsent(index, GlobalKey.new),
                      label: model.fields[index].label(lang),
                      value: model.displayAt(index, bangla: bangla),
                      focused: index == model.focusedIndex,
                      typing: index == model.focusedIndex && model.isTyping,
                      range: model.rangeAt(index),
                      onTap: () => model.focus(index),
                    ),
                  ),
                ),
                const Divider(height: 1),
                _InputBar(model: model, lang: lang, bangla: bangla),
                MeasurementKeypad(
                  bangla: bangla,
                  fractionsEnabled: model.fractionsEnabled,
                  decimalEnabled: model.decimalEnabled,
                  nextLabel: model.isLast ? l10n.keyDone : l10n.keyNext,
                  onDigit: model.digit,
                  onDecimal: model.decimalPoint,
                  onFraction: model.fraction,
                  onBackspace: model.backspace,
                  onNext: model.next,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TopControls extends StatelessWidget {
  const _TopControls({
    required this.model,
    required this.takenOnText,
    required this.hasNote,
    required this.onPickDate,
    required this.onEditNote,
  });

  final MeasurementFormModel model;
  final String takenOnText;
  final bool hasNote;
  final VoidCallback onPickDate;
  final VoidCallback onEditNote;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          SegmentedButton<MeasureUnit>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: MeasureUnit.inch,
                label: Text(l10n.unitInch),
              ),
              ButtonSegment(value: MeasureUnit.cm, label: Text(l10n.unitCm)),
            ],
            selected: {model.unit},
            onSelectionChanged: (value) => model.setUnit(value.first),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: ActionChip(
                avatar: const Icon(Icons.event, size: 18),
                label: Text(
                  takenOnText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onPressed: onPickDate,
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: l10n.noteLabel,
            isSelected: hasNote,
            icon: const Icon(Icons.sticky_note_2_outlined),
            selectedIcon: const Icon(Icons.sticky_note_2),
            onPressed: onEditNote,
          ),
        ],
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.label,
    required this.value,
    required this.focused,
    required this.typing,
    required this.range,
    required this.onTap,
    super.key,
  });

  final String label;
  final String? value;
  final bool focused;
  final bool typing;
  final RangeStatus range;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final warning = switch (range) {
      RangeStatus.ok => null,
      RangeStatus.tooLow => l10n.rangeLow,
      RangeStatus.tooHigh => l10n.rangeHigh,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: focused ? scheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(label, style: theme.textTheme.titleMedium),
                        if (warning != null)
                          Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                size: 16,
                                color: scheme.error,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  warning,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  Text(
                    value ?? '—',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: value == null
                          ? scheme.onSurfaceVariant
                          : (typing ? scheme.primary : scheme.onSurface),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.model,
    required this.lang,
    required this.bangla,
  });

  final MeasurementFormModel model;
  final String lang;
  final bool bangla;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('prev-field'),
            tooltip: l10n.previousField,
            icon: const Icon(Icons.keyboard_arrow_up),
            onPressed: model.isFirst ? null : model.previous,
          ),
          Expanded(
            child: Text(
              model.focusedField.label(lang),
              style: theme.textTheme.titleMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            model.displayAt(model.focusedIndex, bangla: bangla) ?? '—',
            key: const ValueKey('input-value'),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}
