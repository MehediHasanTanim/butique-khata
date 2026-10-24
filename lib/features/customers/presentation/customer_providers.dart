import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/core/ids/id_generator.dart';
import 'package:tailor_khata/features/customers/data/deleted_customers.dart';
import 'package:tailor_khata/features/customers/data/drift_customer_repository.dart';
import 'package:tailor_khata/features/customers/domain/customer.dart';
import 'package:tailor_khata/features/customers/domain/customer_repository.dart';
import 'package:tailor_khata/features/customers/domain/save_customer.dart';

final idGeneratorProvider = Provider<IdGenerator>(
  (ref) => const UuidV7Generator(),
);

final customerRepositoryProvider = Provider<CustomerRepository>(
  (ref) => DriftCustomerRepository(ref.watch(appDatabaseProvider)),
);

final saveCustomerProvider = Provider<SaveCustomer>(
  (ref) => SaveCustomer(
    ref.watch(customerRepositoryProvider),
    ref.watch(clockProvider),
    ref.watch(idGeneratorProvider),
  ),
);

final deleteCustomerProvider = Provider<DeleteCustomer>(
  (ref) => DeleteCustomer(
    ref.watch(customerRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// Text typed in the customer search box (already debounced by the UI).
class CustomerSearchQuery extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;
}

final customerSearchQueryProvider =
    NotifierProvider<CustomerSearchQuery, String>(CustomerSearchQuery.new);

/// Customers for the list screen: everyone, or the search results.
final customerListProvider = StreamProvider.autoDispose<List<Customer>>((ref) {
  final repo = ref.watch(customerRepositoryProvider);
  final query = ref.watch(customerSearchQueryProvider);
  return query.trim().isEmpty ? repo.watchAll() : repo.watchSearch(query);
});

final customerProvider = StreamProvider.autoDispose.family<Customer?, String>(
  (ref, id) => ref.watch(customerRepositoryProvider).watchById(id),
);

final deletedCustomerRepositoryProvider = Provider<DeletedCustomerRepository>(
  (ref) => DeletedCustomerRepository(ref.watch(appDatabaseProvider)),
);

final deletedCustomersProvider =
    StreamProvider.autoDispose<List<DeletedCustomer>>(
      (ref) => ref.watch(deletedCustomerRepositoryProvider).watchDeleted(),
    );
