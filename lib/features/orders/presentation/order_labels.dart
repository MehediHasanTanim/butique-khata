import 'package:tailor_khata/features/orders/domain/order.dart';
import 'package:tailor_khata/features/orders/domain/order_status.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

/// Localized names for order enums.
extension OrderStatusLabel on OrderStatus {
  String label(AppL10n l10n) => switch (this) {
    OrderStatus.received => l10n.statusReceived,
    OrderStatus.cut => l10n.statusCut,
    OrderStatus.stitching => l10n.statusStitching,
    OrderStatus.finishing => l10n.statusFinishing,
    OrderStatus.ready => l10n.statusReady,
    OrderStatus.delivered => l10n.statusDelivered,
  };
}

extension PayMethodLabel on PayMethod {
  String label(AppL10n l10n) => switch (this) {
    PayMethod.cash => l10n.methodCash,
    PayMethod.bkash => l10n.methodBkash,
    PayMethod.nagad => l10n.methodNagad,
    PayMethod.bank => l10n.methodBank,
    PayMethod.other => l10n.methodOther,
  };
}

extension PaymentKindLabel on PaymentKind {
  String label(AppL10n l10n) => switch (this) {
    PaymentKind.advance => l10n.paymentKindAdvance,
    PaymentKind.payment => l10n.paymentKindPayment,
    PaymentKind.refund => l10n.paymentKindRefund,
    PaymentKind.adjustment => l10n.paymentKindAdjustment,
  };
}
