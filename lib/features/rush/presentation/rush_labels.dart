import 'package:tailor_khata/core/l10n/digit_formatter.dart';
import 'package:tailor_khata/features/rush/domain/season.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

extension SeasonKindLabel on SeasonKind {
  String label(AppL10n l10n) => switch (this) {
    SeasonKind.eidFitr => l10n.seasonKindEidFitr,
    SeasonKind.eidAdha => l10n.seasonKindEidAdha,
    SeasonKind.puja => l10n.seasonKindPuja,
    SeasonKind.pohelaBoishakh => l10n.seasonKindBoishakh,
    SeasonKind.wedding => l10n.seasonKindWedding,
    SeasonKind.custom => l10n.seasonKindCustom,
  };
}

/// Short weekday name; [weekday] follows `DateTime.weekday` (Monday = 1).
String weekdayLabel(AppL10n l10n, int weekday) => switch (weekday) {
  1 => l10n.weekday1,
  2 => l10n.weekday2,
  3 => l10n.weekday3,
  4 => l10n.weekday4,
  5 => l10n.weekday5,
  6 => l10n.weekday6,
  _ => l10n.weekday7,
};

/// Work units ×100 shown as garments: `20`, `2.5`, `0.6`.
String formatGarments(int units, {bool bangla = false}) {
  final whole = units / 100;
  final text = units % 100 == 0
      ? '${units ~/ 100}'
      : (units % 10 == 0 ? whole.toStringAsFixed(1) : whole.toStringAsFixed(2));
  return DigitFormatter.format(text, bangla: bangla);
}

/// Parses `20`, `2.5`, `০.৬` into work units ×100; null when invalid or ≤ 0.
int? parseGarments(String input) {
  final text = DigitFormatter.toLatin(input).trim();
  final value = double.tryParse(text);
  if (value == null || value <= 0 || value > 100000) return null;
  return (value * 100).round();
}
