import 'package:flutter/material.dart';

/// Full-width primary action with a 56 dp target.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final child = icon == null
        ? Text(label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [Icon(icon), const SizedBox(width: 8), Text(label)],
          );
    return SizedBox(
      width: double.infinity,
      child: FilledButton(onPressed: onPressed, child: child),
    );
  }
}
