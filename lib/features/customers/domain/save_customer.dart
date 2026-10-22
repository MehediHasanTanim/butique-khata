import 'package:tailor_khata/core/errors/result.dart';
import 'package:tailor_khata/core/ids/id_generator.dart';
import 'package:tailor_khata/core/text/name_normalizer.dart';
import 'package:tailor_khata/core/text/phone_normalizer.dart';
import 'package:tailor_khata/core/time/clock.dart';
import 'package:tailor_khata/features/customers/domain/customer.dart';
import 'package:tailor_khata/features/customers/domain/customer_repository.dart';

/// Another active customer already has this phone number (C-8).
class DuplicatePhoneFailure extends Failure {
  const DuplicatePhoneFailure(this.existing)
    : super('customer.duplicate_phone', 'Phone number already in use');

  final Customer existing;
}

/// Validates [CustomerInput] and creates or updates a customer (C-1, C-8).
class SaveCustomer {
  SaveCustomer(this._repo, this._clock, this._ids);

  final CustomerRepository _repo;
  final Clock _clock;
  final IdGenerator _ids;

  /// Creates a customer, or updates [existing] when given. A duplicate phone
  /// returns [DuplicatePhoneFailure] unless [allowDuplicatePhone] is true.
  Future<Result<Customer>> call(
    CustomerInput input, {
    Customer? existing,
    bool allowDuplicatePhone = false,
  }) async {
    final name = NameNormalizer.clean(input.name);
    if (name.isEmpty) {
      return const Result.err(Failure('customer.name_required'));
    }

    String? phone;
    if (input.phone.trim().isNotEmpty) {
      final parsed = PhoneNormalizer.parse(input.phone);
      if (parsed == null) {
        return const Result.err(Failure('customer.phone_invalid'));
      }
      phone = parsed.e164;
      if (!allowDuplicatePhone) {
        final other = await _repo.findByPhone(phone, excludeId: existing?.id);
        if (other != null) return Result.err(DuplicatePhoneFailure(other));
      }
    }

    final now = _clock.now();
    String? emptyToNull(String value) {
      final cleaned = value.trim();
      return cleaned.isEmpty ? null : cleaned;
    }

    if (existing == null) {
      final customer = Customer(
        id: _ids.newId(),
        name: name,
        phone: phone,
        address: emptyToNull(input.address),
        note: emptyToNull(input.note),
        createdAt: now,
        updatedAt: now,
      );
      await _repo.insert(customer);
      return Result.ok(customer);
    }
    final updated = existing.copyWith(
      name: name,
      phone: () => phone,
      address: () => emptyToNull(input.address),
      note: () => emptyToNull(input.note),
      updatedAt: now,
    );
    await _repo.update(updated);
    return Result.ok(updated);
  }
}

/// Soft-deletes a customer; history is kept and can be restored (B-8).
class DeleteCustomer {
  DeleteCustomer(this._repo, this._clock);

  final CustomerRepository _repo;
  final Clock _clock;

  Future<void> call(String id) => _repo.softDelete(id, _clock.now());
  Future<void> undo(String id) => _repo.restore(id, _clock.now());
}
