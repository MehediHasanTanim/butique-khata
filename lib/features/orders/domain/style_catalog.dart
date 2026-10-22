/// One choice inside a style group, e.g. "band" collar.
class StyleOption {
  const StyleOption(this.key, this.en, this.bn);

  final String key;
  final String en;
  final String bn;

  String label(String languageCode) => languageCode == 'bn' ? bn : en;
}

/// A style question for a garment, e.g. collar or pocket (O-2).
class StyleGroup {
  const StyleGroup(this.key, this.en, this.bn, this.options);

  final String key;
  final String en;
  final String bn;
  final List<StyleOption> options;

  String label(String languageCode) => languageCode == 'bn' ? bn : en;

  StyleOption? option(String key) =>
      options.where((o) => o.key == key).firstOrNull;
}

/// Built-in style options per garment. Owners will be able to edit these in
/// settings later.
class StyleCatalog {
  const StyleCatalog._();

  static const _collar = StyleGroup('collar', 'Collar', 'কলার', [
    StyleOption('band', 'Band', 'ব্যান্ড'),
    StyleOption('shirt', 'Shirt collar', 'শার্ট কলার'),
    StyleOption('mandarin', 'Mandarin', 'ম্যান্ডারিন'),
    StyleOption('none', 'No collar', 'কলার নেই'),
  ]);
  static const _pocket = StyleGroup('pocket', 'Pocket', 'পকেট', [
    StyleOption('side', 'Side', 'পাশে'),
    StyleOption('chest', 'Chest', 'বুকে'),
    StyleOption('both', 'Side + chest', 'পাশে ও বুকে'),
    StyleOption('none', 'None', 'নেই'),
  ]);
  static const _cuff = StyleGroup('cuff', 'Cuff', 'কাফ', [
    StyleOption('plain', 'Plain', 'সাধারণ'),
    StyleOption('button', 'Button', 'বোতাম'),
    StyleOption('french', 'French', 'ফ্রেঞ্চ'),
  ]);
  static const _buttons = StyleGroup('buttons', 'Buttons', 'বোতাম', [
    StyleOption('plain', 'Plain', 'সাধারণ'),
    StyleOption('fancy', 'Fancy', 'নকশা করা'),
    StyleOption('wooden', 'Wooden', 'কাঠের'),
  ]);
  static const _lining = StyleGroup('lining', 'Lining', 'লাইনিং', [
    StyleOption('none', 'None', 'নেই'),
    StyleOption('cotton', 'Cotton', 'সুতি'),
    StyleOption('satin', 'Satin', 'সাটিন'),
  ]);
  static const _embroidery = StyleGroup(
    'embroidery',
    'Embroidery',
    'এমব্রয়ডারি',
    [
      StyleOption('none', 'None', 'নেই'),
      StyleOption('neckline', 'Neckline', 'গলায়'),
      StyleOption('chest', 'Chest', 'বুকে'),
      StyleOption('full', 'Full', 'পুরো'),
    ],
  );

  /// Style groups for the garment with [garmentKey] (e.g. `panjabi`).
  static List<StyleGroup> forGarment(String garmentKey) => switch (garmentKey) {
    'panjabi' => [_collar, _pocket, _cuff, _buttons, _embroidery],
    'shirt' => [_collar, _pocket, _cuff, _buttons],
    'pant' => [_pocket, _lining],
    'blazer' => [_pocket, _buttons, _lining],
    'salwar_kameez' => [_embroidery, _lining],
    'blouse' => [_embroidery, _lining],
    _ => const [],
  };

  /// Readable summary like `Collar: Band · Pocket: Side`, for chips and slips.
  static String summarize(
    String garmentKey,
    Map<String, String> chosen,
    String languageCode,
  ) {
    final parts = <String>[];
    for (final group in forGarment(garmentKey)) {
      final key = chosen[group.key];
      final option = key == null ? null : group.option(key);
      if (option != null) {
        parts.add(
          '${group.label(languageCode)}: ${option.label(languageCode)}',
        );
      }
    }
    return parts.join(' · ');
  }
}
