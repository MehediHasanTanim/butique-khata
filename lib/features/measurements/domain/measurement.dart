import 'package:tailor_khata/core/units/length.dart';

enum MeasureUnit {
  inch,
  cm;

  String get dbValue => this == inch ? 'in' : 'cm';

  static MeasureUnit fromDb(String value) =>
      value == 'cm' ? MeasureUnit.cm : MeasureUnit.inch;
}

enum MeasurementStatus {
  active,
  error;

  static MeasurementStatus fromDb(String value) =>
      value == 'error' ? MeasurementStatus.error : MeasurementStatus.active;
}

/// How a garment made from a measurement version turned out (H-6).
enum FitOutcome {
  confirmed,
  altered;

  String get dbValue => name;

  static FitOutcome? fromDb(String? value) => switch (value) {
    'confirmed' => FitOutcome.confirmed,
    'altered' => FitOutcome.altered,
    _ => null,
  };
}

/// One field of a garment template.
class FieldTemplate {
  const FieldTemplate({
    required this.key,
    required this.labelEn,
    required this.labelBn,
    required this.sortOrder,
    this.minMm10,
    this.maxMm10,
  });

  final String key;
  final String labelEn;
  final String labelBn;
  final int sortOrder;
  final int? minMm10;
  final int? maxMm10;

  String label(String languageCode) => languageCode == 'bn' ? labelBn : labelEn;
}

/// A garment type with its ordered, non-archived fields.
class GarmentInfo {
  const GarmentInfo({
    required this.id,
    required this.key,
    required this.labelEn,
    required this.labelBn,
    required this.fields,
  });

  final String id;
  final String key;
  final String labelEn;
  final String labelBn;
  final List<FieldTemplate> fields;

  String label(String languageCode) => languageCode == 'bn' ? labelBn : labelEn;
}

/// One saved, immutable version of a customer's measurements for a garment.
class Measurement {
  const Measurement({
    required this.id,
    required this.customerId,
    required this.garmentTypeId,
    required this.version,
    required this.takenOn,
    required this.unit,
    required this.status,
    required this.createdAt,
    required this.values,
    this.takenBy,
    this.note,
    this.supersedesId,
    this.fitOutcome,
  });

  final String id;
  final String customerId;
  final String garmentTypeId;
  final int version;
  final FitOutcome? fitOutcome;

  /// Calendar date, `YYYY-MM-DD`.
  final String takenOn;
  final String? takenBy;
  final String? note;
  final MeasureUnit unit;
  final MeasurementStatus status;
  final String? supersedesId;
  final DateTime createdAt;

  /// Field key → value. Fields left blank at entry are absent.
  final Map<String, Length> values;
}

/// Data needed to save a new version.
class NewMeasurement {
  const NewMeasurement({
    required this.customerId,
    required this.garmentTypeId,
    required this.takenOn,
    required this.unit,
    required this.values,
    this.takenBy,
    this.note,
    this.supersedesId,
  });

  final String customerId;
  final String garmentTypeId;
  final String takenOn;
  final MeasureUnit unit;
  final Map<String, Length> values;
  final String? takenBy;
  final String? note;
  final String? supersedesId;
}

enum RangeStatus { ok, tooLow, tooHigh }

/// Soft range check (§4.4): out-of-range only warns, never blocks.
RangeStatus checkRange(FieldTemplate field, Length value) {
  final min = field.minMm10;
  final max = field.maxMm10;
  if (min != null && value.mm10 < min) return RangeStatus.tooLow;
  if (max != null && value.mm10 > max) return RangeStatus.tooHigh;
  return RangeStatus.ok;
}
