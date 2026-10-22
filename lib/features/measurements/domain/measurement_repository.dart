import 'package:tailor_khata/features/measurements/domain/measurement.dart';

abstract class MeasurementRepository {
  /// Garment types (non-archived) with their fields, ordered for display.
  Future<List<GarmentInfo>> garments();
  Stream<List<GarmentInfo>> watchGarments();

  /// Saves a new version (previous versions are never touched, H-1).
  /// Version numbers are assigned atomically per (customer, garment).
  Future<Measurement> create(NewMeasurement input);

  Future<Measurement?> byId(String id);

  /// Newest active version: highest `takenOn`, then highest `version`.
  Future<Measurement?> latest(String customerId, String garmentTypeId);

  /// Newest active version per garment type for a customer.
  Stream<List<Measurement>> watchLatestPerGarment(String customerId);

  /// All versions for a garment, newest first.
  Future<List<Measurement>> versions(
    String customerId,
    String garmentTypeId, {
    bool includeErrors = false,
  });

  /// Live list of versions for a garment, newest first.
  Stream<List<Measurement>> watchVersions(
    String customerId,
    String garmentTypeId, {
    bool includeErrors = false,
  });

  /// Flags a version as "entered in error" (hidden, never deleted).
  Future<void> markError(String id);

  /// Reverses [markError].
  Future<void> restore(String id);

  /// Records how the garment fitted; null clears it (H-6).
  Future<void> setFitOutcome(String id, FitOutcome? outcome);
}
