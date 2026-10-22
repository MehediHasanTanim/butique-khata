import 'package:tailor_khata/features/customers/domain/customer.dart';

abstract class CustomerRepository {
  Future<Customer?> byId(String id);
  Stream<Customer?> watchById(String id);

  /// All active customers sorted by name.
  Stream<List<Customer>> watchAll();

  /// Active customers matching [query] (name tokens by prefix, or phone digits
  /// by substring). An empty query behaves like [watchAll] limited to [limit].
  Stream<List<Customer>> watchSearch(String query, {int limit = 100});

  /// Same as [watchSearch] as a one-shot future.
  Future<List<Customer>> search(String query, {int limit = 100});

  /// Active customer whose phone matches [phone] (E.164), ignoring
  /// [excludeId].
  Future<Customer?> findByPhone(String phone, {String? excludeId});

  Future<void> insert(Customer customer);
  Future<void> update(Customer customer);
  Future<void> softDelete(String id, DateTime at);
  Future<void> restore(String id, DateTime at);
  Future<int> count();
}
