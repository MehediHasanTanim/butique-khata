import 'package:tailor_khata/core/units/length.dart';

/// Definition of one measurement field in a built-in template.
class FieldDef {
  const FieldDef(this.key, this.en, this.bn, this.minInches, this.maxInches);

  final String key;
  final String en;
  final String bn;

  /// Soft range in inches; values outside only produce a warning (§4.4).
  final int minInches;
  final int maxInches;

  int get minMm10 => minInches * Length.mm10PerInch;
  int get maxMm10 => maxInches * Length.mm10PerInch;
}

class GarmentTemplate {
  const GarmentTemplate(this.key, this.en, this.bn, this.fields);

  final String key;
  final String en;
  final String bn;
  final List<FieldDef> fields;

  /// Stable id so every device seeds identical rows.
  String get id => 'gt_$key';

  String fieldId(FieldDef field) => '$id:${field.key}';
}

/// Default templates from Spec §5.2.5. Owners can edit them later (M-4).
class BuiltInTemplates {
  const BuiltInTemplates._();

  static const _length = FieldDef('length', 'Length', 'লম্বা', 15, 60);
  static const _chest = FieldDef('chest', 'Chest', 'বুক', 20, 60);
  static const _waist = FieldDef('waist', 'Waist', 'কোমর', 20, 60);
  static const _hip = FieldDef('hip', 'Hip', 'হিপ', 20, 65);
  static const _shoulder = FieldDef('shoulder', 'Shoulder', 'কাঁধ', 10, 25);
  static const _sleeve = FieldDef('sleeve', 'Sleeve', 'হাতা', 10, 40);
  static const _cuff = FieldDef('cuff', 'Cuff', 'কাফ', 5, 15);
  static const _collar = FieldDef('collar', 'Collar', 'কলার', 10, 22);
  static const _neck = FieldDef('neck', 'Neck', 'গলা', 8, 25);
  static const _bottom = FieldDef('bottom', 'Bottom', 'মুহরি', 5, 30);
  static const _thigh = FieldDef('thigh', 'Thigh', 'রান', 10, 40);
  static const _armhole = FieldDef('armhole', 'Armhole', 'আর্মহোল', 10, 30);
  static const _neckFront = FieldDef(
    'neck_front',
    'Neck front',
    'গলা (সামনে)',
    3,
    15,
  );
  static const _neckBack = FieldDef(
    'neck_back',
    'Neck back',
    'গলা (পেছনে)',
    3,
    15,
  );

  static const List<GarmentTemplate> all = [
    GarmentTemplate('panjabi', 'Panjabi / Kurta', 'পাঞ্জাবি', [
      _length,
      _chest,
      _waist,
      _hip,
      _shoulder,
      _sleeve,
      _cuff,
      _collar,
      _neck,
      _bottom,
    ]),
    GarmentTemplate('shirt', 'Shirt', 'শার্ট', [
      _length,
      _chest,
      _waist,
      _hip,
      _shoulder,
      _sleeve,
      _cuff,
      _collar,
    ]),
    GarmentTemplate('pant', 'Pant / Trouser', 'প্যান্ট', [
      FieldDef('length', 'Length', 'লম্বা', 25, 50),
      FieldDef('waist', 'Waist', 'কোমর', 20, 60),
      _hip,
      _thigh,
      FieldDef('knee', 'Knee', 'হাঁটু', 8, 30),
      FieldDef('bottom', 'Bottom', 'মুহরি', 5, 30),
      FieldDef('rise', 'Rise', 'রাইজ', 6, 18),
      FieldDef('fly', 'Fly', 'ফ্লাই', 4, 12),
    ]),
    GarmentTemplate('pajama', 'Pajama', 'পায়জামা', [
      FieldDef('length', 'Length', 'লম্বা', 25, 50),
      FieldDef('waist', 'Waist', 'কোমর', 20, 60),
      _hip,
      _thigh,
      FieldDef('bottom', 'Bottom', 'মুহরি', 5, 30),
    ]),
    GarmentTemplate('blazer', 'Blazer / Coat', 'ব্লেজার', [
      _length,
      _chest,
      _waist,
      _shoulder,
      _sleeve,
      FieldDef('back', 'Back', 'পিঠ', 10, 30),
    ]),
    GarmentTemplate('salwar_kameez', 'Salwar Kameez', 'সালোয়ার কামিজ', [
      FieldDef('kameez_length', 'Kameez length', 'কামিজ লম্বা', 25, 60),
      FieldDef('chest', 'Chest / Bust', 'বুক', 20, 60),
      _waist,
      _hip,
      _shoulder,
      _sleeve,
      _armhole,
      _neckFront,
      _neckBack,
      FieldDef('salwar_length', 'Salwar length', 'সালোয়ার লম্বা', 25, 50),
      FieldDef('salwar_waist', 'Salwar waist', 'সালোয়ার কোমর', 20, 60),
      FieldDef('salwar_hip', 'Salwar hip', 'সালোয়ার হিপ', 20, 65),
      FieldDef('salwar_bottom', 'Salwar bottom', 'সালোয়ার মুহরি', 5, 30),
    ]),
    GarmentTemplate('blouse', 'Blouse', 'ব্লাউজ', [
      _length,
      FieldDef('bust', 'Bust', 'বাস্ট', 20, 60),
      _waist,
      _shoulder,
      _sleeve,
      _armhole,
      _neckFront,
      _neckBack,
      FieldDef('dart_point', 'Dart point', 'ডার্ট পয়েন্ট', 5, 15),
    ]),
  ];

  static GarmentTemplate byKey(String key) =>
      all.firstWhere((t) => t.key == key);
}
