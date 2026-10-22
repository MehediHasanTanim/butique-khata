import 'dart:math';

/// A synthetic customer used for performance and UI testing.
class SeedCustomer {
  const SeedCustomer({required this.name, required this.phone});

  final String name;
  final String phone;
}

/// Deterministic generator of realistic Bangla and English customer data
/// (S0-10). Persistence is added in Sprint 1 once the customer table exists;
/// until then this feeds the perf harness and the debug screen.
class SeedGenerator {
  SeedGenerator({int seed = 42}) : _random = Random(seed);

  final Random _random;

  static const _englishFirst = [
    'Rahim',
    'Karim',
    'Abdul',
    'Mizanur',
    'Shafiq',
    'Nasir',
    'Jahid',
    'Tanvir',
    'Sabbir',
    'Fahim',
    'Ayesha',
    'Fatema',
    'Nusrat',
    'Sumaiya',
    'Rokeya',
    'Taslima',
    'Farhana',
    'Mim',
    'Sadia',
    'Tahmina',
  ];
  static const _englishLast = [
    'Uddin',
    'Hossain',
    'Ahmed',
    'Rahman',
    'Islam',
    'Khan',
    'Chowdhury',
    'Mia',
    'Sarker',
    'Akter',
    'Begum',
    'Khatun',
    'Talukder',
    'Mondal',
  ];
  static const _banglaFirst = [
    'রহিম',
    'করিম',
    'আব্দুল',
    'মিজানুর',
    'শফিক',
    'নাসির',
    'জাহিদ',
    'তানভীর',
    'সাব্বির',
    'ফাহিম',
    'আয়েশা',
    'ফাতেমা',
    'নুসরাত',
    'সুমাইয়া',
    'রোকেয়া',
    'তাসলিমা',
    'ফারহানা',
    'মিম',
    'সাদিয়া',
    'তাহমিনা',
  ];
  static const _banglaLast = [
    'উদ্দিন',
    'হোসেন',
    'আহমেদ',
    'রহমান',
    'ইসলাম',
    'খান',
    'চৌধুরী',
    'মিয়া',
    'সরকার',
    'আক্তার',
    'বেগম',
    'খাতুন',
    'তালুকদার',
    'মণ্ডল',
  ];

  /// Bangladesh mobile numbers are `01` + [3-9] + 8 digits (11 digits).
  static const _operators = ['3', '4', '5', '6', '7', '8', '9'];

  /// Produces [count] customers; about half are named in Bangla.
  List<SeedCustomer> customers(int count) {
    return List.generate(count, (index) {
      final bangla = _random.nextBool();
      final first = _pick(bangla ? _banglaFirst : _englishFirst);
      final last = _pick(bangla ? _banglaLast : _englishLast);
      return SeedCustomer(name: '$first $last', phone: _phone());
    });
  }

  String _phone() {
    final operatorCode = _pick(_operators);
    final tail = _random.nextInt(100000000).toString().padLeft(8, '0');
    return '01$operatorCode$tail';
  }

  T _pick<T>(List<T> items) => items[_random.nextInt(items.length)];
}
