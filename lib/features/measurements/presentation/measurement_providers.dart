import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/features/customers/presentation/customer_providers.dart';
import 'package:tailor_khata/features/measurements/data/drift_measurement_repository.dart';
import 'package:tailor_khata/features/measurements/domain/measurement.dart';
import 'package:tailor_khata/features/measurements/domain/measurement_repository.dart';

final measurementRepositoryProvider = Provider<MeasurementRepository>(
  (ref) => DriftMeasurementRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(clockProvider),
    ref.watch(idGeneratorProvider),
  ),
);

final garmentsProvider = StreamProvider.autoDispose<List<GarmentInfo>>(
  (ref) => ref.watch(measurementRepositoryProvider).watchGarments(),
);

/// Newest active measurement per garment for one customer.
final latestMeasurementsProvider = StreamProvider.autoDispose
    .family<List<Measurement>, String>(
      (ref, customerId) => ref
          .watch(measurementRepositoryProvider)
          .watchLatestPerGarment(customerId),
    );
