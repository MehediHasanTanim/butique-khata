import 'package:flutter/material.dart';
import 'package:tailor_khata/features/orders/domain/order_status.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

/// Colour-coded chip showing an item's production status.
class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final (label, color) = switch (status) {
      OrderStatus.received => (l10n.statusReceived, const Color(0xFF6D6D6D)),
      OrderStatus.cut => (l10n.statusCut, const Color(0xFF8D5A00)),
      OrderStatus.stitching => (l10n.statusStitching, const Color(0xFF1565C0)),
      OrderStatus.finishing => (l10n.statusFinishing, const Color(0xFF6A1B9A)),
      OrderStatus.ready => (l10n.statusReady, const Color(0xFF2E7D32)),
      OrderStatus.delivered => (l10n.statusDelivered, const Color(0xFF00695C)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}
