import 'package:tailor_khata/features/measurements/domain/measurement.dart';
import 'package:tailor_khata/features/measurements/domain/measurement_diff.dart';
import 'package:tailor_khata/features/measurements/domain/measurement_repository.dart';

sealed class SaveMeasurementOutcome {
  const SaveMeasurementOutcome();
}

/// A new version was stored.
final class MeasurementSaved extends SaveMeasurementOutcome {
  const MeasurementSaved(this.measurement);
  final Measurement measurement;
}

/// Nothing differs from the latest version, so no row was created (H-5).
/// [latest] is the existing version that already holds these values.
final class MeasurementUnchanged extends SaveMeasurementOutcome {
  const MeasurementUnchanged(this.latest);
  final Measurement latest;
}

/// Saves a measurement as version n+1 linked to the version it replaces, or
/// does nothing when the values equal the latest version (H-1, H-5).
class SaveMeasurement {
  SaveMeasurement(this._repo);

  final MeasurementRepository _repo;

  Future<SaveMeasurementOutcome> call(NewMeasurement input) async {
    final latest = await _repo.latest(input.customerId, input.garmentTypeId);
    if (latest != null && sameValues(latest.values, input.values)) {
      return MeasurementUnchanged(latest);
    }
    final saved = await _repo.create(
      NewMeasurement(
        customerId: input.customerId,
        garmentTypeId: input.garmentTypeId,
        takenOn: input.takenOn,
        unit: input.unit,
        values: input.values,
        takenBy: input.takenBy,
        note: input.note,
        supersedesId: latest?.id,
      ),
    );
    return MeasurementSaved(saved);
  }
}
