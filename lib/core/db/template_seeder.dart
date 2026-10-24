import 'package:drift/drift.dart';
import 'package:tailor_khata/core/db/app_database.dart';
import 'package:tailor_khata/features/measurements/domain/built_in_templates.dart';

/// Inserts the built-in garment templates. Idempotent: existing rows (which
/// the owner may have edited) are never overwritten.
Future<void> seedBuiltInTemplates(AppDatabase db) async {
  await db.batch((batch) {
    for (var i = 0; i < BuiltInTemplates.all.length; i++) {
      final template = BuiltInTemplates.all[i];
      batch.insert(
        db.garmentType,
        GarmentTypeCompanion.insert(
          id: template.id,
          key: template.key,
          labelEn: template.en,
          labelBn: template.bn,
          isBuiltin: const Value(true),
          sortOrder: Value(i),
          workUnits: Value(template.workUnits),
        ),
        mode: InsertMode.insertOrIgnore,
      );
      for (var j = 0; j < template.fields.length; j++) {
        final field = template.fields[j];
        batch.insert(
          db.measurementField,
          MeasurementFieldCompanion.insert(
            id: template.fieldId(field),
            garmentTypeId: template.id,
            key: field.key,
            labelEn: field.en,
            labelBn: field.bn,
            minMm10: Value(field.minMm10),
            maxMm10: Value(field.maxMm10),
            sortOrder: j,
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
    }
  });
}
