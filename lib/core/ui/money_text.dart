import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/core/money/money.dart';

/// Renders [amount] in the current language's digits. With [highlightDue]
/// a positive amount is red and a zero amount green (Spec P-3).
class MoneyText extends ConsumerWidget {
  const MoneyText(
    this.amount, {
    this.style,
    this.highlightDue = false,
    super.key,
  });

  final Money amount;
  final TextStyle? style;
  final bool highlightDue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bangla = ref.watch(useBanglaDigitsProvider);
    final scheme = Theme.of(context).colorScheme;
    final color = !highlightDue
        ? null
        : amount.isPositive
        ? scheme.error
        : const Color(0xFF2E7D32);
    final base = style ?? Theme.of(context).textTheme.titleMedium;
    return Text(
      amount.format(bangla: bangla),
      style: base?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
