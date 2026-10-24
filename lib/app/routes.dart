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
  static String history(String customerId, String garmentKey) =>
      '/customer/$customerId/history/$garmentKey';
  static String compare(
    String customerId,
    String garmentKey, {
    String? earlierId,
    String? laterId,
  }) {
    final query = [
      if (earlierId != null) 'a=$earlierId',
      if (laterId != null) 'b=$laterId',
    ].join('&');
    return '/customer/$customerId/compare/$garmentKey'
        '${query.isEmpty ? '' : '?$query'}';
  }

  static String trend(String customerId, String garmentKey) =>
      '/customer/$customerId/trend/$garmentKey';

  static const pickCustomer = '/pick-customer';
  static String order(String id) => '/order/$id';
  static String newOrder(String customerId, {String? duplicateOf}) =>
      '/customer/$customerId/order/new'
      '${duplicateOf == null ? '' : '?dup=$duplicateOf'}';

  static String slip(String orderId) => '/order/$orderId/slip';
  static String deliveries({String? tab}) =>
      '/deliveries${tab == null ? '' : '?tab=$tab'}';
  static const search = '/search';
  static const settingsReminders = '/more/reminders';
  static const settingsMessages = '/more/messages';

  static String rushSetup({String? seasonId}) =>
      '/rush/setup${seasonId == null ? '' : '?id=$seasonId'}';
  static const rushCalendar = '/rush/calendar';
  static const rushBatches = '/rush/batches';
  static const rushList = '/rush/list';
}
