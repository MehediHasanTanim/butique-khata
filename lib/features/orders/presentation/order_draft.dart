import 'package:flutter/foundation.dart';
import 'package:tailor_khata/core/money/money.dart';
import 'package:tailor_khata/features/measurements/domain/measurement.dart';
import 'package:tailor_khata/features/orders/domain/order.dart';

/// One garment being added to a new order.
class DraftItem {
  DraftItem({required this.garment, this.qty = 1});

  final GarmentInfo garment;
  int qty;

  /// Latest saved measurement for this customer and garment, if any.
  Measurement? latest;

  /// The version this garment will be cut from (the snapshot link).
  String? measurementSetId;
  Measurement? measurement;

  Map<String, String> style = {};
  FabricSource fabric = FabricSource.shop;
  String colour = '';
  String note = '';
  String priceText = '';

  Money? get price => Money.tryParse(priceText);
}

/// Everything entered in the new-order wizard (S3-04). Pure state: the
/// screen decides when each part is valid.
class OrderDraft extends ChangeNotifier {
  OrderDraft({required this.customerId, required this.deliveryDate});

  final String customerId;
  final List<DraftItem> items = [];

  String deliveryDate;
  String? trialDate;
  bool urgent = false;
  String discountText = '';
  String advanceText = '';
  PayMethod method = PayMethod.cash;
  String note = '';
  String? parentOrderId;

  void changed() => notifyListeners();

  void addItem(DraftItem item) {
    items.add(item);
    notifyListeners();
  }

  void removeItem(DraftItem item) {
    items.remove(item);
    notifyListeners();
  }

  /// True when every garment has a price.
  bool get pricesComplete => items.every((i) => i.price != null);

  Money get subtotal => Money.sum(items.map((i) => i.price ?? Money.zero));

  /// Null when empty; zero for an unparsable text (caller reports the error).
  Money? get discount =>
      discountText.trim().isEmpty ? Money.zero : Money.tryParse(discountText);

  Money? get advance =>
      advanceText.trim().isEmpty ? Money.zero : Money.tryParse(advanceText);

  Money get total => subtotal - (discount ?? Money.zero);

  Money get due => total - (advance ?? Money.zero);

  /// Order ready to hand to `CreateOrder`; null if prices/amounts are bad.
  NewOrder? build({required String paidOn}) {
    final discount = this.discount;
    final advance = this.advance;
    if (discount == null || advance == null || !pricesComplete) return null;
    return NewOrder(
      customerId: customerId,
      deliveryDate: deliveryDate,
      trialDate: trialDate,
      discount: discount,
      urgent: urgent,
      note: note.trim().isEmpty ? null : note.trim(),
      parentOrderId: parentOrderId,
      items: [
        for (final i in items)
          NewOrderItem(
            garmentTypeId: i.garment.id,
            price: i.price!,
            qty: i.qty,
            measurementSetId: i.measurementSetId,
            fabricSource: i.fabric,
            colour: i.colour.trim().isEmpty ? null : i.colour.trim(),
            style: i.style,
            note: i.note.trim().isEmpty ? null : i.note.trim(),
          ),
      ],
      advance: advance.isZero
          ? null
          : NewPayment(
              orderId: '',
              amount: advance,
              method: method,
              paidOn: paidOn,
              kind: PaymentKind.advance,
            ),
    );
  }
}
