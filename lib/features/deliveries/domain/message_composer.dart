import 'package:tailor_khata/core/l10n/digit_formatter.dart';
import 'package:tailor_khata/core/time/date_format.dart';
import 'package:tailor_khata/features/deliveries/domain/message_templates.dart';
import 'package:tailor_khata/features/orders/domain/order.dart';

/// Builds the text sent to a customer (D-3, D-5).
///
/// [template] is the shop's wording (edited or built in), [garments] the
/// garment names of the order, [shop] the name to sign with. Numbers and
/// dates follow [languageCode]. [newDate] overrides the delivery date for
/// "delivery moved" messages.
String composeMessage({
  required String template,
  required OrderDetail detail,
  required List<String> garments,
  required String shop,
  required String languageCode,
  String? newDate,
  bool includeDue = true,
}) {
  final bangla = languageCode == 'bn';
  final due = detail.money.due;
  final dueText = (includeDue && due.isPositive)
      ? due.format(bangla: bangla)
      : '';
  return MessageTemplates.render(template, {
    'name': detail.customerName,
    'order': DigitFormatter.format('${detail.order.number}', bangla: bangla),
    'garment': garments.join(languageCode == 'bn' ? ', ' : ', '),
    'due': MessageTemplates.dueSentence(dueText, languageCode),
    'date': formatStoredDate(
      newDate ?? detail.order.deliveryDate,
      languageCode,
    ),
    'shop': shop,
  });
}
