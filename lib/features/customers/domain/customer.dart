/// A customer of the shop.
class Customer {
  const Customer({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.phone,
    this.address,
    this.note,
  });

  final String id;
  final String name;

  /// Canonical E.164 number (`+8801712345678`) or null.
  final String? phone;
  final String? address;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Local-style number for display: `01712345678` for Bangladesh numbers.
  String? get phoneDisplay {
    final p = phone;
    if (p == null) return null;
    return p.startsWith('+880') ? '0${p.substring(4)}' : p;
  }

  /// First letter(s) for avatars.
  String get initial =>
      name.isEmpty ? '?' : String.fromCharCode(name.runes.first);

  Customer copyWith({
    String? name,
    String? Function()? phone,
    String? Function()? address,
    String? Function()? note,
    DateTime? updatedAt,
  }) => Customer(
    id: id,
    name: name ?? this.name,
    phone: phone != null ? phone() : this.phone,
    address: address != null ? address() : this.address,
    note: note != null ? note() : this.note,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// Raw form values before validation.
class CustomerInput {
  const CustomerInput({
    required this.name,
    this.phone = '',
    this.address = '',
    this.note = '',
  });

  final String name;
  final String phone;
  final String address;
  final String note;
}
