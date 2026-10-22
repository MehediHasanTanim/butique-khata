import 'package:tailor_khata/core/l10n/digit_formatter.dart';
import 'package:tailor_khata/core/text/phone_normalizer.dart';

enum MessageKind {
  /// "Your garment is ready" (D-3).
  ready,

  /// A reminder about a balance.
  due,

  /// The delivery date changed (D-5).
  moved;

  /// Settings key under which an edited template is stored.
  String get settingKey => 'tpl.$name';
}

/// Message wording with `{placeholders}` the tailor can edit (D-3).
///
/// Placeholders: `{name}` `{order}` `{garment}` `{due}` `{date}` `{shop}`.
/// `{due}` expands to a sentence about the balance, or to nothing.
class MessageTemplates {
  const MessageTemplates._();

  static const Map<MessageKind, String> _english = {
    MessageKind.ready:
        'Assalamu alaikum {name}. Your {garment} (order #{order}) is ready '
        'for pickup.{due} Thank you, {shop}',
    MessageKind.due:
        'Assalamu alaikum {name}. A gentle reminder about order #{order}.'
        '{due} Thank you, {shop}',
    MessageKind.moved:
        'Assalamu alaikum {name}. The delivery of your order #{order} is now '
        '{date}. Sorry for the change. {shop}',
  };

  static const Map<MessageKind, String> _bangla = {
    MessageKind.ready:
        'আসসালামু আলাইকুম {name}। আপনার {garment} (অর্ডার #{order}) তৈরি '
        'হয়েছে, নিয়ে যেতে পারেন।{due} ধন্যবাদ, {shop}',
    MessageKind.due:
        'আসসালামু আলাইকুম {name}। অর্ডার #{order} সম্পর্কে একটি অনুস্মারক।'
        '{due} ধন্যবাদ, {shop}',
    MessageKind.moved:
        'আসসালামু আলাইকুম {name}। আপনার অর্ডার #{order}-এর ডেলিভারি এখন '
        '{date}। অসুবিধার জন্য দুঃখিত। {shop}',
  };

  /// Built-in wording for [kind] in [languageCode] (`en` or `bn`).
  static String defaultFor(MessageKind kind, String languageCode) =>
      (languageCode == 'bn' ? _bangla : _english)[kind]!;

  /// Fills `{key}` placeholders; unknown ones are left as typed.
  static String render(String template, Map<String, String> values) => template
      .replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) {
        return values[m[1]] ?? m[0]!;
      })
      .replaceAll(RegExp(r' {2,}'), ' ')
      .trim();

  /// Sentence about a balance, e.g. ` Balance due: ৳700.`; empty if none.
  static String dueSentence(String formattedAmount, String languageCode) {
    if (formattedAmount.isEmpty) return '';
    return languageCode == 'bn'
        ? ' বাকি আছে: $formattedAmount।'
        : ' Balance due: $formattedAmount.';
  }

  /// Digits in Bangla for Bangla messages.
  static String digits(String text, String languageCode) =>
      DigitFormatter.format(text, bangla: languageCode == 'bn');
}

/// Links that open the phone's messaging apps with the text prefilled (D-3).
/// No API and no cost: the tailor presses send themself.
class MessageLinks {
  const MessageLinks._();

  /// `sms:+8801712345678?body=...`, or null if [phone] is missing/invalid.
  static Uri? sms(String? phone, String body) {
    final number = _e164(phone);
    if (number == null) return null;
    return Uri.parse('sms:$number?body=${Uri.encodeComponent(body)}');
  }

  /// `https://wa.me/8801712345678?text=...` (digits only, no plus).
  static Uri? whatsApp(String? phone, String body) {
    final number = _e164(phone);
    if (number == null) return null;
    return Uri.https('wa.me', '/${number.substring(1)}', {'text': body});
  }

  static String? _e164(String? phone) {
    if (phone == null || phone.trim().isEmpty) return null;
    return PhoneNormalizer.parse(phone)?.e164;
  }
}
