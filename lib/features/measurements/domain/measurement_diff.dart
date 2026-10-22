import 'package:tailor_khata/core/units/length.dart';

enum DeltaKind { same, changed, added, removed }

/// Difference of one field between an earlier and a later measurement.
class FieldDelta {
  const FieldDelta({
    required this.key,
    required this.kind,
    this.before,
    this.after,
  });

  final String key;
  final DeltaKind kind;
  final Length? before;
  final Length? after;

  /// `after - before`; null unless the field exists in both versions.
  Length? get delta =>
      (before != null && after != null) ? after! - before! : null;

  bool get isChange => kind != DeltaKind.same;
}

/// Compares an [earlier] and a [later] set of values by field key (H-3).
///
/// Works across garment types because it only looks at shared keys. Result
/// order follows [order] when given (template order), then any remaining
/// keys alphabetically.
List<FieldDelta> diffMeasurements(
  Map<String, Length> earlier,
  Map<String, Length> later, {
  List<String> order = const [],
}) {
  final keys = <String>{...earlier.keys, ...later.keys};
  final ordered = <String>[
    for (final key in order)
      if (keys.contains(key)) key,
    ...(keys.where((k) => !order.contains(k)).toList()..sort()),
  ];
  return [
    for (final key in ordered)
      FieldDelta(
        key: key,
        before: earlier[key],
        after: later[key],
        kind: switch ((earlier[key], later[key])) {
          (null, _) => DeltaKind.added,
          (_, null) => DeltaKind.removed,
          (final a?, final b?) => a == b ? DeltaKind.same : DeltaKind.changed,
        },
      ),
  ];
}

/// True when both maps hold exactly the same fields with equal values.
bool sameValues(Map<String, Length> a, Map<String, Length> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

/// Default size of a change that deserves a "please confirm" prompt (§4.4).
const int kChangeWarnThresholdMm10 = 381; // 1.5 inch

/// Fields that moved by more than [thresholdMm10] between [earlier] and
/// [later]. Added/removed fields are not large changes.
List<FieldDelta> largeChanges(
  Map<String, Length> earlier,
  Map<String, Length> later, {
  int thresholdMm10 = kChangeWarnThresholdMm10,
}) => diffMeasurements(earlier, later)
    .where(
      (d) => d.kind == DeltaKind.changed && d.delta!.abs.mm10 > thresholdMm10,
    )
    .toList();
