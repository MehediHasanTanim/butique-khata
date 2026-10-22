import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tailor_khata/core/l10n/digit_formatter.dart';

/// Big-button numeric pad for measurements (M-2). 5 columns × 4 rows:
///
///     1 2 3 ⅛ ¼
///     4 5 6 ⅜ ½
///     7 8 9 ⅝ ¾
///     ⌫ 0 . ⅞ Next
///
/// Every key is at least 48 dp high. It never opens the system keyboard, so
/// nothing is covered on a small screen.
class MeasurementKeypad extends StatelessWidget {
  const MeasurementKeypad({
    required this.onDigit,
    required this.onDecimal,
    required this.onFraction,
    required this.onBackspace,
    required this.onNext,
    this.fractionsEnabled = true,
    this.decimalEnabled = true,
    this.bangla = false,
    this.nextLabel = 'Next',
    this.keyHeight = 52,
    super.key,
  });

  final ValueChanged<int> onDigit;
  final VoidCallback onDecimal;

  /// Called with the numerator over 8 (1 = ⅛ … 7 = ⅞).
  final ValueChanged<int> onFraction;
  final VoidCallback onBackspace;
  final VoidCallback onNext;
  final bool fractionsEnabled;
  final bool decimalEnabled;
  final bool bangla;
  final String nextLabel;
  final double keyHeight;

  static const _fractionGlyphs = {
    1: '⅛',
    2: '¼',
    3: '⅜',
    4: '½',
    5: '⅝',
    6: '¾',
    7: '⅞',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget digit(int d) => _Key(
      keyId: 'key-$d',
      label: DigitFormatter.format('$d', bangla: bangla),
      height: keyHeight,
      onTap: () => onDigit(d),
    );
    Widget fraction(int n) => _Key(
      keyId: 'key-frac-$n',
      label: _fractionGlyphs[n]!,
      height: keyHeight,
      color: scheme.secondaryContainer,
      textColor: scheme.onSecondaryContainer,
      onTap: fractionsEnabled ? () => onFraction(n) : null,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _row([digit(1), digit(2), digit(3), fraction(1), fraction(2)]),
          _row([digit(4), digit(5), digit(6), fraction(3), fraction(4)]),
          _row([digit(7), digit(8), digit(9), fraction(5), fraction(6)]),
          _row([
            _Key(
              keyId: 'key-backspace',
              icon: Icons.backspace_outlined,
              height: keyHeight,
              color: scheme.surfaceContainerHighest,
              onTap: onBackspace,
            ),
            digit(0),
            _Key(
              keyId: 'key-decimal',
              label: '.',
              height: keyHeight,
              onTap: decimalEnabled ? onDecimal : null,
            ),
            fraction(7),
            _Key(
              keyId: 'key-next',
              label: nextLabel,
              height: keyHeight,
              color: scheme.primary,
              textColor: scheme.onPrimary,
              onTap: onNext,
            ),
          ]),
        ],
      ),
    );
  }

  Widget _row(List<Widget> children) =>
      Row(children: [for (final child in children) Expanded(child: child)]);
}

class _Key extends StatelessWidget {
  const _Key({
    required this.keyId,
    required this.height,
    required this.onTap,
    this.label,
    this.icon,
    this.color,
    this.textColor,
  });

  final String keyId;
  final String? label;
  final IconData? icon;
  final double height;
  final VoidCallback? onTap;
  final Color? color;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    final foreground = (textColor ?? scheme.onSurface).withValues(
      alpha: enabled ? 1 : 0.35,
    );
    return Padding(
      padding: const EdgeInsets.all(3),
      child: Material(
        key: ValueKey(keyId),
        color: color ?? scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap!();
                },
          child: SizedBox(
            height: height,
            child: Center(
              child: icon != null
                  ? Icon(icon, color: foreground)
                  : Text(
                      label!,
                      maxLines: 1,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
