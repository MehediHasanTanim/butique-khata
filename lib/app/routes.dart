/// Route paths. Detail screens are pushed above the tab shell (full screen).
abstract class AppRoutes {
  static const home = '/home';
  static const customers = '/customers';
  static const orders = '/orders';
  static const rush = '/rush';
  static const more = '/more';
  static const seed = '/more/seed';

  static const customerNew = '/customer/new';
  static String customer(String id) => '/customer/$id';
  static String customerEdit(String id) => '/customer/$id/edit';
  static String measure(String customerId, String garmentKey) =>
      '/customer/$customerId/measure/$garmentKey';
}
