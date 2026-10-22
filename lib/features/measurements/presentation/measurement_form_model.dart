import 'package:flutter/foundation.dart';
import 'package:tailor_khata/core/units/length.dart';
import 'package:tailor_khata/features/measurements/domain/measurement.dart';
import 'package:tailor_khata/features/measurements/domain/measurement_input.dart';

/// State behind the measurement entry screen: which field is focused, the
/// number being typed, and the values entered so far (S1-07, S1-08).
class MeasurementFormModel extends ChangeNotifier {
  MeasurementFormModel({
    required this.fields,
    MeasureUnit unit = MeasureUnit.inch,
    Map<String, Length> initial = const {},
    this.autoAdvance = true,
    // ignore: prefer_initializing_formals
  }) : _unit = unit,
       _values = Map.of(initial);

  final List<FieldTemplate> fields;

  /// Move to the next field automatically after a fraction (or a complete
  /// cm value) is entered.
  final bool autoAdvance;

  final Map<String, Length> _values;
  MeasureUnit _unit;
  int _focused = 0;
  MeasurementInput? _buffer;

  MeasureUnit get unit => _unit;
  int get focusedIndex => _focused;
  FieldTemplate get focusedField => fields[_focused];
  bool get isFirst => _focused == 0;
  bool get isLast => _focused == fields.length - 1;

  /// True while the focused field shows the user's typing rather than the
  /// stored value.
  bool get isTyping => _buffer != null;

  bool get fractionsEnabled =>
      _unit == MeasureUnit.inch && (_buffer?.canAddFraction ?? true);
  bool get decimalEnabled => _buffer?.canAddDecimal ?? true;

  /// Value of the field at [index], including live typing for the focused one.
  Length? valueAt(int index) {
    if (index == _focused && _buffer != null) return _buffer!.length;
    return _values[fields[index].key];
  }

  /// Text to show for [index]; null when blank. [bangla] swaps digits.
  String? displayAt(int index, {bool bangla = false}) {
    if (index == _focused && _buffer != null) {
      final text = _buffer!.text;
      return text.isEmpty ? null : _digits(text, bangla);
    }
    final value = _values[fields[index].key];
    if (value == null) return null;
    return _unit == MeasureUnit.inch
        ? value.toInchFraction(bangla: bangla)
        : value.toCm(bangla: bangla);
  }

  RangeStatus rangeAt(int index) {
    final value = valueAt(index);
    return value == null ? RangeStatus.ok : checkRange(fields[index], value);
  }

  int get filledCount => List.generate(
    fields.length,
    (i) => valueAt(i),
  ).where((v) => v != null).length;

  bool get hasValues => filledCount > 0;

  /// Commits typing and returns all entered values.
  Map<String, Length> toValues() {
    _commit();
    return Map.unmodifiable(_values);
  }

  // ---- keys ---------------------------------------------------------------

  void digit(int d) => _type((b) => b.digit(d));

  void decimalPoint() => _type((b) => b.decimalPoint());

  void fraction(int eighths) => _type((b) => b.fraction(eighths));

  void backspace() {
    if (_buffer == null) {
      // First backspace on a stored value clears the whole field.
      if (_values.remove(focusedField.key) != null) notifyListeners();
      return;
    }
    _buffer = _buffer!.backspace();
    notifyListeners();
  }

  void next() {
    _commit();
    if (!isLast) _focused++;
    notifyListeners();
  }

  void previous() {
    _commit();
    if (!isFirst) _focused--;
    notifyListeners();
  }

  void focus(int index) {
    if (index == _focused || index < 0 || index >= fields.length) return;
    _commit();
    _focused = index;
    notifyListeners();
  }

  void setUnit(MeasureUnit unit) {
    if (unit == _unit) return;
    _commit();
    _unit = unit;
    notifyListeners();
  }

  // ---- internals ----------------------------------------------------------

  void _type(MeasurementInput Function(MeasurementInput) key) {
    final before = _buffer ?? MeasurementInput.empty(_unit);
    final after = key(before);
    _buffer = after;
    notifyListeners();
    // A fraction (inch) or the last cm decimal ends the number.
    if (after.isComplete && after != before) _advanceIfDone();
  }

  void _advanceIfDone() {
    if (autoAdvance && (_buffer?.isComplete ?? false) && !isLast) next();
  }

  void _commit() {
    final buffer = _buffer;
    if (buffer == null) return;
    final value = buffer.length;
    if (value == null) {
      _values.remove(focusedField.key);
    } else {
      _values[focusedField.key] = value;
    }
    _buffer = null;
  }

  static String _digits(String text, bool bangla) {
    if (!bangla) return text;
    const map = '০১২৩৪৫৬৭৮৯';
    return text.replaceAllMapped(RegExp(r'\d'), (m) => map[int.parse(m[0]!)]);
  }
}
