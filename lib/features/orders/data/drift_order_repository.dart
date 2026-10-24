import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:tailor_khata/core/db/app_database.dart';
import 'package:tailor_khata/core/ids/id_generator.dart';
import 'package:tailor_khata/core/money/money.dart';
import 'package:tailor_khata/core/text/name_normalizer.dart';
import 'package:tailor_khata/core/time/clock.dart';
import 'package:tailor_khata/features/orders/domain/delivery.dart';
import 'package:tailor_khata/features/orders/domain/order.dart';
import 'package:tailor_khata/features/orders/domain/order_repository.dart';
import 'package:tailor_khata/features/orders/domain/order_status.dart';

class DriftOrderRepository implements OrderRepository {
  DriftOrderRepository(this._db, this._clock, this._ids);

  final AppDatabase _db;
  final Clock _clock;
  final IdGenerator _ids;

  static const String _entity = 'customer_order';
  static const int _maxAttempts = 5;

  // ---- mapping ------------------------------------------------------------

  static DateTime _time(int millis) =>
      DateTime.fromMillisecondsSinceEpoch(millis);

  static Order _order(OrderRow r) => Order(
    id: r.id,
    number: r.number,
    customerId: r.customerId,
    deliveryDate: r.deliveryDate,
    trialDate: r.trialDate,
    discount: Money(r.discount),
    urgent: r.urgent,
    status: OrderStatus.fromDb(r.status),
    note: r.note,
    parentOrderId: r.parentOrderId,
    createdAt: _time(r.createdAt),
    updatedAt: _time(r.updatedAt),
    cancelledAt: r.cancelledAt == null ? null : _time(r.cancelledAt!),
    cancelReason: r.cancelReason,
    seasonId: r.seasonId,
    overbooked: r.overbooked,
  );

  static OrderItem _item(OrderItemRow r) => OrderItem(
    id: r.id,
    orderId: r.orderId,
    garmentTypeId: r.garmentTypeId,
    qty: r.qty,
    price: Money(r.price),
    status: OrderStatus.fromDb(r.status),
    statusChangedAt: _time(r.statusChangedAt),
    measurementSetId: r.measurementSetId,
    fabricSource: FabricSource.fromDb(r.fabricSource),
    colour: r.colour,
    style: r.styleJson == null
        ? const {}
        : (jsonDecode(r.styleJson!) as Map<String, dynamic>).map(
            (k, v) => MapEntry(k, v as String),
          ),
    note: r.note,
    workerId: r.workerId,
    workUnits: r.workUnits,
  );

  static Payment _payment(PaymentRow r) => Payment(
    id: r.id,
    orderId: r.orderId,
    amount: Money(r.amount),
    kind: PaymentKind.fromDb(r.kind),
    method: PayMethod.fromDb(r.method),
    paidOn: r.paidOn,
    note: r.note,
    createdAt: _time(r.createdAt),
  );

  // ---- create -------------------------------------------------------------

  @override
  Future<OrderDetail> create(NewOrder input) async {
    for (var attempt = 1; ; attempt++) {
      try {
        final id = await _db.transaction(() => _insertOrder(input));
        return (await detail(id))!;
      } on sqlite.SqliteException catch (error) {
        // Another order took the same slip number: try the next one.
        if (error.resultCode != 19 || attempt >= _maxAttempts) rethrow;
      }
    }
  }

  Future<String> _insertOrder(NewOrder input) async {
    final maxExpr = _db.customerOrder.number.max();
    final maxQuery = _db.selectOnly(_db.customerOrder)..addColumns([maxExpr]);
    final number = ((await maxQuery.getSingle()).read(maxExpr) ?? 0) + 1;

    final now = _clock.now().millisecondsSinceEpoch;
    final orderId = _ids.newId();
    await _db
        .into(_db.customerOrder)
        .insert(
          CustomerOrderCompanion.insert(
            id: orderId,
            number: number,
            customerId: input.customerId,
            deliveryDate: input.deliveryDate,
            trialDate: Value(input.trialDate),
            discount: Value(input.discount.poisha),
            urgent: Value(input.urgent),
            status: OrderStatus.received.dbValue,
            note: Value(input.note),
            parentOrderId: Value(input.parentOrderId),
            seasonId: Value(input.seasonId),
            overbooked: Value(input.overbooked),
            createdAt: now,
            updatedAt: now,
          ),
        );
    final itemIds = [for (final _ in input.items) _ids.newId()];
    await _db.batch((batch) {
      batch.insertAll(_db.orderItem, [
        for (var i = 0; i < input.items.length; i++)
          OrderItemCompanion.insert(
            id: itemIds[i],
            orderId: orderId,
            garmentTypeId: input.items[i].garmentTypeId,
            qty: Value(input.items[i].qty),
            price: input.items[i].price.poisha,
            measurementSetId: Value(input.items[i].measurementSetId),
            fabricSource: Value(input.items[i].fabricSource?.dbValue),
            colour: Value(input.items[i].colour),
            styleJson: Value(
              input.items[i].style.isEmpty
                  ? null
                  : jsonEncode(input.items[i].style),
            ),
            note: Value(input.items[i].note),
            status: OrderStatus.received.dbValue,
            statusChangedAt: now,
            workUnits: Value(input.items[i].workUnits * input.items[i].qty),
          ),
      ]);
      for (var i = 0; i < input.items.length; i++) {
        for (final photo in input.items[i].photos) {
          batch.insert(
            _db.attachment,
            AttachmentCompanion.insert(
              id: _ids.newId(),
              ownerType: 'order_item',
              ownerId: itemIds[i],
              path: photo.path,
              thumbPath: Value(photo.thumbPath),
              createdAt: now,
            ),
          );
        }
      }
    });
    final advance = input.advance;
    if (advance != null && advance.amount.isPositive) {
      await _insertPayment(
        NewPayment(
          orderId: orderId,
          amount: advance.amount,
          method: advance.method,
          paidOn: advance.paidOn,
          kind: PaymentKind.advance,
          note: advance.note,
        ),
      );
    }
    await _audit(orderId, 'created', '#$number');
    return orderId;
  }

  // ---- reads --------------------------------------------------------------

  @override
  Future<OrderDetail?> detail(String id) async {
    final row = await (_db.select(
      _db.customerOrder,
    )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();
    if (row == null) return null;
    final customer = await (_db.select(
      _db.customer,
    )..where((t) => t.id.equals(row.customerId))).getSingle();
    final items =
        await (_db.select(_db.orderItem)
              ..where((t) => t.orderId.equals(id))
              ..orderBy([(t) => OrderingTerm.asc(t.statusChangedAt)]))
            .get();
    final payments =
        await (_db.select(_db.payment)
              ..where((t) => t.orderId.equals(id))
              ..orderBy([
                (t) => OrderingTerm.asc(t.paidOn),
                (t) => OrderingTerm.asc(t.createdAt),
              ]))
            .get();
    return OrderDetail(
      order: _order(row),
      customerName: customer.name,
      items: items.map(_item).toList(),
      payments: payments.map(_payment).toList(),
    );
  }

  @override
  Stream<OrderDetail?> watchDetail(String id) => _db
      .customSelect(
        'SELECT 1',
        readsFrom: {
          _db.customerOrder,
          _db.orderItem,
          _db.payment,
          _db.customer,
        },
      )
      .watch()
      .asyncMap((_) => detail(id));

  @override
  Stream<List<OrderSummary>> watchSummaries({
    String? customerId,
    bool openOnly = false,
    OrderFilter? filter,
  }) {
    final where = <String>['o.deleted_at IS NULL'];
    final vars = <Variable<Object>>[];
    if (customerId != null) {
      where.add('o.customer_id = ?');
      vars.add(Variable<String>(customerId));
    }
    if (openOnly) {
      where.add("o.cancelled_at IS NULL AND o.status != 'delivered'");
    }
    if (filter != null) _applyFilter(filter, where, vars);
    return _db
        .customSelect(
          '$_summarySelect WHERE ${where.join(' AND ')} '
          'ORDER BY o.delivery_date ASC, o.number ASC',
          variables: vars,
          readsFrom: _summaryTables,
        )
        .watch()
        .map(_mapSummaries);
  }

  static const String _summarySelect =
      'SELECT o.*, c.name AS customer_name, m.total AS total, '
      'm.paid AS paid, '
      '(SELECT COUNT(*) FROM order_item i WHERE i.order_id = o.id) '
      'AS item_count '
      'FROM customer_order o '
      'JOIN customer c ON c.id = o.customer_id '
      'JOIN v_order_money m ON m.order_id = o.id';

  Set<TableInfo<Table, dynamic>> get _summaryTables => {
    _db.customerOrder,
    _db.orderItem,
    _db.payment,
    _db.customer,
  };

  List<OrderSummary> _mapSummaries(List<QueryRow> rows) => [
    for (final r in rows)
      OrderSummary(
        order: _order(_db.customerOrder.map(r.data)),
        customerName: r.read<String>('customer_name'),
        itemCount: r.read<int>('item_count'),
        money: OrderMoney(
          total: Money(r.read<int>('total')),
          paid: Money(r.read<int>('paid')),
        ),
      ),
  ];

  void _applyFilter(
    OrderFilter filter,
    List<String> where,
    List<Variable<Object>> vars,
  ) {
    final text = NameNormalizer.normalize(filter.query);
    if (text.isNotEmpty) {
      final digits = text.replaceAll(RegExp(r'\D'), '');
      final number = int.tryParse(text.replaceFirst('#', '').trim());
      final clauses = <String>["c.name_norm LIKE '%' || ? || '%'"];
      vars.add(Variable<String>(text));
      if (number != null) {
        clauses.add('o.number = ?');
        vars.add(Variable<int>(number));
      }
      if (digits.length >= 3) {
        clauses.add("c.phone_digits LIKE '%' || ? || '%'");
        vars.add(Variable<String>(digits));
      }
      where.add('(${clauses.join(' OR ')})');
    }
    if (filter.statuses.isNotEmpty) {
      where.add(
        'o.status IN (${List.filled(filter.statuses.length, '?').join(',')})',
      );
      for (final status in filter.statuses) {
        vars.add(Variable<String>(status.dbValue));
      }
    }
    if (filter.dueOnly) {
      where.add('o.cancelled_at IS NULL AND m.total - m.paid > 0');
    }
    if (filter.garmentTypeId != null) {
      where.add(
        'EXISTS (SELECT 1 FROM order_item gi WHERE gi.order_id = o.id '
        'AND gi.garment_type_id = ?)',
      );
      vars.add(Variable<String>(filter.garmentTypeId!));
    }
    if (filter.from != null) {
      where.add('o.delivery_date >= ?');
      vars.add(Variable<String>(filter.from!));
    }
    if (filter.to != null) {
      where.add('o.delivery_date <= ?');
      vars.add(Variable<String>(filter.to!));
    }
  }

  // ---- deliveries / dashboard --------------------------------------------

  static const String _openWhere =
      "o.deleted_at IS NULL AND o.cancelled_at IS NULL AND o.status != 'delivered'";

  @override
  Future<List<OrderSummary>> deliveriesPage({
    String? from,
    String? to,
    DeliveryCursor? after,
    int limit = 30,
  }) async {
    final where = <String>[_openWhere];
    final vars = <Variable<Object>>[];
    if (from != null) {
      where.add('o.delivery_date >= ?');
      vars.add(Variable<String>(from));
    }
    if (to != null) {
      where.add('o.delivery_date <= ?');
      vars.add(Variable<String>(to));
    }
    if (after != null) {
      where.add('(o.delivery_date, o.number) > (?, ?)');
      vars
        ..add(Variable<String>(after.date))
        ..add(Variable<int>(after.number));
    }
    vars.add(Variable<int>(limit));
    final rows = await _db
        .customSelect(
          '$_summarySelect WHERE ${where.join(' AND ')} '
          'ORDER BY o.delivery_date ASC, o.number ASC LIMIT ?',
          variables: vars,
          readsFrom: _summaryTables,
        )
        .get();
    return _mapSummaries(rows);
  }

  @override
  Future<List<OrderSummary>> uncollected({required int olderThanMillis}) async {
    final rows = await _db
        .customSelect(
          '$_summarySelect WHERE $_openWhere AND o.status = \'ready\' '
          'AND (SELECT MAX(i.status_changed_at) FROM order_item i '
          'WHERE i.order_id = o.id) <= ? '
          'ORDER BY o.delivery_date ASC, o.number ASC',
          variables: [Variable<int>(olderThanMillis)],
          readsFrom: _summaryTables,
        )
        .get();
    return _mapSummaries(rows);
  }

  @override
  Stream<DeliveryCounts> watchDeliveryCounts({
    required DeliveryBuckets buckets,
    required int uncollectedBeforeMillis,
  }) => _db
      .customSelect(
        'SELECT '
        'COALESCE(SUM(CASE WHEN o.delivery_date < ? THEN 1 ELSE 0 END), 0) AS overdue, '
        'COALESCE(SUM(CASE WHEN o.delivery_date = ? THEN 1 ELSE 0 END), 0) AS today, '
        'COALESCE(SUM(CASE WHEN o.delivery_date = ? THEN 1 ELSE 0 END), 0) AS tomorrow, '
        'COALESCE(SUM(CASE WHEN o.delivery_date BETWEEN ? AND ? THEN 1 ELSE 0 END), 0) AS week, '
        "COALESCE(SUM(CASE WHEN o.status = 'ready' AND "
        '(SELECT MAX(i.status_changed_at) FROM order_item i '
        'WHERE i.order_id = o.id) <= ? THEN 1 ELSE 0 END), 0) AS uncollected '
        'FROM customer_order o WHERE $_openWhere',
        variables: [
          Variable<String>(buckets.today),
          Variable<String>(buckets.today),
          Variable<String>(buckets.tomorrow),
          Variable<String>(buckets.weekStart),
          Variable<String>(buckets.weekEnd),
          Variable<int>(uncollectedBeforeMillis),
        ],
        readsFrom: {_db.customerOrder, _db.orderItem},
      )
      .watchSingle()
      .map(
        (r) => DeliveryCounts(
          overdue: r.read<int>('overdue'),
          today: r.read<int>('today'),
          tomorrow: r.read<int>('tomorrow'),
          week: r.read<int>('week'),
          uncollected: r.read<int>('uncollected'),
        ),
      );

  @override
  Stream<List<DeliveryDay>> watchOpenDeliveryDays() => _db
      .customSelect(
        'SELECT o.delivery_date AS day, COUNT(*) AS cnt, MIN(o.id) AS first_id '
        'FROM customer_order o WHERE $_openWhere '
        'GROUP BY o.delivery_date ORDER BY o.delivery_date',
        readsFrom: {_db.customerOrder},
      )
      .watch()
      .map(
        (rows) => [
          for (final r in rows)
            DeliveryDay(
              date: r.read<String>('day'),
              count: r.read<int>('cnt'),
              firstOrderId: r.read<String>('first_id'),
            ),
        ],
      );

  @override
  Stream<DashboardStats> watchDashboard({
    required String today,
    required int startOfTodayMillis,
  }) => _db
      .customSelect(
        'SELECT '
        '(SELECT COUNT(*) FROM customer_order o WHERE $_openWhere '
        'AND o.delivery_date = ?) AS due_today, '
        '(SELECT COUNT(*) FROM customer_order o WHERE $_openWhere '
        'AND o.delivery_date < ?) AS overdue, '
        '(SELECT COALESCE(SUM($_dueExpr), 0) FROM customer_order o '
        'JOIN v_order_money m ON m.order_id = o.id '
        'WHERE o.deleted_at IS NULL AND o.cancelled_at IS NULL) AS total_due, '
        '(SELECT COUNT(*) FROM customer_order o WHERE o.deleted_at IS NULL '
        'AND o.created_at >= ?) AS received_today',
        variables: [
          Variable<String>(today),
          Variable<String>(today),
          Variable<int>(startOfTodayMillis),
        ],
        readsFrom: {_db.customerOrder, _db.orderItem, _db.payment},
      )
      .watchSingle()
      .map(
        (r) => DashboardStats(
          dueToday: r.read<int>('due_today'),
          overdue: r.read<int>('overdue'),
          totalDue: Money(r.read<int>('total_due')),
          receivedToday: r.read<int>('received_today'),
        ),
      );

  static const String _dueExpr =
      'CASE WHEN m.total - m.paid > 0 THEN m.total - m.paid ELSE 0 END';

  @override
  Stream<List<CustomerDue>> watchDues() => _db
      .customSelect(
        'SELECT c.id AS customer_id, c.name AS customer_name, '
        'SUM($_dueExpr) AS due, COUNT(*) AS order_count, '
        'MIN(o.delivery_date) AS oldest '
        'FROM customer_order o '
        'JOIN customer c ON c.id = o.customer_id '
        'JOIN v_order_money m ON m.order_id = o.id '
        'WHERE o.deleted_at IS NULL AND o.cancelled_at IS NULL '
        'AND m.total - m.paid > 0 '
        'GROUP BY c.id ORDER BY due DESC, c.name_norm ASC',
        readsFrom: {
          _db.customerOrder,
          _db.orderItem,
          _db.payment,
          _db.customer,
        },
      )
      .watch()
      .map(
        (rows) => [
          for (final r in rows)
            CustomerDue(
              customerId: r.read<String>('customer_id'),
              customerName: r.read<String>('customer_name'),
              due: Money(r.read<int>('due')),
              orderCount: r.read<int>('order_count'),
              oldestDeliveryDate: r.read<String>('oldest'),
            ),
        ],
      );

  @override
  Stream<Money> watchCustomerDue(String customerId) => _db
      .customSelect(
        'SELECT COALESCE(SUM($_dueExpr), 0) AS due '
        'FROM customer_order o '
        'JOIN v_order_money m ON m.order_id = o.id '
        'WHERE o.customer_id = ? AND o.deleted_at IS NULL '
        'AND o.cancelled_at IS NULL',
        variables: [Variable<String>(customerId)],
        readsFrom: {_db.customerOrder, _db.orderItem, _db.payment},
      )
      .watchSingle()
      .map((r) => Money(r.read<int>('due')));

  // ---- payments -----------------------------------------------------------

  @override
  Future<Payment> addPayment(NewPayment payment) => _db.transaction(() async {
    if (payment.amount.isZero) {
      throw ArgumentError.value(payment.amount, 'amount', 'must not be zero');
    }
    final id = await _insertPayment(payment);
    await _audit(
      payment.orderId,
      'payment_added',
      '${payment.kind.dbValue} ${payment.amount.format(symbol: false)}',
    );
    final row = await (_db.select(
      _db.payment,
    )..where((t) => t.id.equals(id))).getSingle();
    return _payment(row);
  });

  Future<String> _insertPayment(NewPayment p) async {
    final id = _ids.newId();
    await _db
        .into(_db.payment)
        .insert(
          PaymentCompanion.insert(
            id: id,
            orderId: p.orderId,
            amount: p.amount.poisha,
            kind: p.kind.dbValue,
            method: p.method.dbValue,
            paidOn: p.paidOn,
            note: Value(p.note),
            createdAt: _clock.now().millisecondsSinceEpoch,
          ),
        );
    return id;
  }

  // ---- status -------------------------------------------------------------

  @override
  Future<void> setItemStatus(
    String itemId,
    OrderStatus to, {
    bool dueConfirmed = false,
  }) => _db.transaction(() async {
    final item = await (_db.select(
      _db.orderItem,
    )..where((t) => t.id.equals(itemId))).getSingle();
    await _requireOpen(item.orderId);
    if (to == OrderStatus.delivered && !dueConfirmed) {
      await _requireNoDue(item.orderId);
    }
    final from = OrderStatus.fromDb(item.status);
    if (!from.canMoveTo(to)) {
      throw StateError('Cannot move item from $from to $to');
    }
    await _moveItem(item, to);
    await _rollUp(item.orderId);
  });

  @override
  Future<void> setAllItemsStatus(
    String orderId,
    OrderStatus to, {
    bool dueConfirmed = false,
  }) => _db.transaction(() async {
    await _requireOpen(orderId);
    if (to == OrderStatus.delivered && !dueConfirmed) {
      await _requireNoDue(orderId);
    }
    final items = await (_db.select(
      _db.orderItem,
    )..where((t) => t.orderId.equals(orderId))).get();
    for (final item in items) {
      if (OrderStatus.fromDb(item.status).canMoveTo(to)) {
        await _moveItem(item, to);
      }
    }
    await _rollUp(orderId);
  });

  @override
  Future<int> moveItems(Iterable<String> itemIds, OrderStatus to) {
    if (to == OrderStatus.delivered) {
      throw ArgumentError.value(to, 'to', 'use deliverAll for hand-over');
    }
    return _db.transaction(() async {
      var moved = 0;
      final orders = <String>{};
      for (final id in itemIds) {
        final item = await (_db.select(
          _db.orderItem,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        if (item == null) continue;
        final order = await (_db.select(
          _db.customerOrder,
        )..where((t) => t.id.equals(item.orderId))).getSingle();
        if (order.cancelledAt != null || order.deletedAt != null) continue;
        if (!OrderStatus.fromDb(item.status).canMoveTo(to)) continue;
        await _moveItem(item, to);
        orders.add(item.orderId);
        moved++;
      }
      for (final orderId in orders) {
        await _rollUp(orderId);
      }
      return moved;
    });
  }

  @override
  Future<OrderStatus?> advanceOrder(String orderId) =>
      _db.transaction(() async {
        final order = await (_db.select(
          _db.customerOrder,
        )..where((t) => t.id.equals(orderId))).getSingleOrNull();
        if (order == null || order.cancelledAt != null) return null;
        final items = await (_db.select(
          _db.orderItem,
        )..where((t) => t.orderId.equals(orderId))).get();
        final current = OrderStatus.rollUp(
          items.map((i) => OrderStatus.fromDb(i.status)),
        );
        final next = current.next;
        if (next == null || next == OrderStatus.delivered) return null;
        for (final item in items) {
          if (OrderStatus.fromDb(item.status).index < next.index) {
            await _moveItem(item, next);
          }
        }
        await _rollUp(orderId);
        return next;
      });

  /// Throws [DueOutstandingError] if the order still has a balance (P-4).
  Future<void> _requireNoDue(String orderId) async {
    final row = await _db
        .customSelect(
          'SELECT total - paid AS due FROM v_order_money WHERE order_id = ?',
          variables: [Variable<String>(orderId)],
          readsFrom: {_db.customerOrder, _db.orderItem, _db.payment},
        )
        .getSingle();
    final due = row.read<int>('due');
    if (due > 0) throw DueOutstandingError(Money(due));
  }

  @override
  Future<void> deliverAll(
    String orderId, {
    Money? collect,
    PayMethod method = PayMethod.cash,
    String? paidOn,
    bool dueConfirmed = false,
  }) => _db.transaction(() async {
    await _requireOpen(orderId);
    if (collect != null && collect.isPositive) {
      await _insertPayment(
        NewPayment(
          orderId: orderId,
          amount: collect,
          method: method,
          paidOn: paidOn ?? Clock.toDateString(_clock.now()),
          kind: PaymentKind.payment,
          note: null,
        ),
      );
      await _audit(
        orderId,
        'payment_added',
        'payment ${collect.format(symbol: false)}',
      );
    }
    if (!dueConfirmed) await _requireNoDue(orderId);
    final items = await (_db.select(
      _db.orderItem,
    )..where((t) => t.orderId.equals(orderId))).get();
    for (final item in items) {
      if (item.status != OrderStatus.delivered.dbValue) {
        await _moveItem(item, OrderStatus.delivered);
      }
    }
    await _rollUp(orderId);
  });

  Future<void> _requireOpen(String orderId) async {
    final order = await (_db.select(
      _db.customerOrder,
    )..where((t) => t.id.equals(orderId))).getSingle();
    if (order.cancelledAt != null) {
      throw StateError('Order is cancelled');
    }
  }

  Future<void> _moveItem(OrderItemRow item, OrderStatus to) async {
    final now = _clock.now().millisecondsSinceEpoch;
    await (_db.update(_db.orderItem)..where((t) => t.id.equals(item.id))).write(
      OrderItemCompanion(
        status: Value(to.dbValue),
        statusChangedAt: Value(now),
      ),
    );
    await _audit(item.orderId, 'item_status', '${item.status} → ${to.dbValue}');
  }

  Future<void> _rollUp(String orderId) async {
    final items = await (_db.select(
      _db.orderItem,
    )..where((t) => t.orderId.equals(orderId))).get();
    final status = OrderStatus.rollUp(
      items.map((i) => OrderStatus.fromDb(i.status)),
    );
    await (_db.update(
      _db.customerOrder,
    )..where((t) => t.id.equals(orderId))).write(
      CustomerOrderCompanion(
        status: Value(status.dbValue),
        updatedAt: Value(_clock.now().millisecondsSinceEpoch),
      ),
    );
  }

  // ---- edit / cancel ------------------------------------------------------

  @override
  Future<void> updateDetails(
    String orderId, {
    String? deliveryDate,
    String? trialDate,
    bool clearTrialDate = false,
    bool? urgent,
    String? note,
    String? reason,
  }) => _db.transaction(() async {
    await _requireOpen(orderId);
    final row = await (_db.select(
      _db.customerOrder,
    )..where((t) => t.id.equals(orderId))).getSingle();
    final changes = <String>[];
    if (deliveryDate != null && deliveryDate != row.deliveryDate) {
      Clock.parseDate(deliveryDate);
      changes.add('delivery ${row.deliveryDate} → $deliveryDate');
    }
    if (clearTrialDate && row.trialDate != null) {
      changes.add('trial ${row.trialDate} → none');
    } else if (trialDate != null && trialDate != row.trialDate) {
      changes.add('trial ${row.trialDate ?? 'none'} → $trialDate');
    }
    if (urgent != null && urgent != row.urgent) {
      changes.add('urgent ${row.urgent} → $urgent');
    }
    if (note != null && note != (row.note ?? '')) {
      changes.add('note changed');
    }
    if (changes.isEmpty) return;
    await (_db.update(
      _db.customerOrder,
    )..where((t) => t.id.equals(orderId))).write(
      CustomerOrderCompanion(
        deliveryDate: Value(deliveryDate ?? row.deliveryDate),
        trialDate: clearTrialDate
            ? const Value(null)
            : (trialDate != null ? Value(trialDate) : const Value.absent()),
        urgent: Value(urgent ?? row.urgent),
        note: note == null
            ? const Value.absent()
            : Value(note.isEmpty ? null : note),
        updatedAt: Value(_clock.now().millisecondsSinceEpoch),
      ),
    );
    final why = (reason == null || reason.trim().isEmpty)
        ? ''
        : ' (${reason.trim()})';
    await _audit(orderId, 'details_changed', '${changes.join('; ')}$why');
  });

  @override
  Future<void> cancel(
    String orderId, {
    required String reason,
    required CancelAdvance advance,
    required String today,
  }) => _db.transaction(() async {
    await _requireOpen(orderId);
    final now = _clock.now().millisecondsSinceEpoch;
    await (_db.update(
      _db.customerOrder,
    )..where((t) => t.id.equals(orderId))).write(
      CustomerOrderCompanion(
        cancelledAt: Value(now),
        cancelReason: Value(reason),
        updatedAt: Value(now),
      ),
    );
    final paidExpr = _db.payment.amount.sum();
    final paidQuery = _db.selectOnly(_db.payment)
      ..addColumns([paidExpr])
      ..where(_db.payment.orderId.equals(orderId));
    final paid = (await paidQuery.getSingle()).read(paidExpr) ?? 0;
    if (advance == CancelAdvance.refund && paid > 0) {
      await _insertPayment(
        NewPayment(
          orderId: orderId,
          amount: Money(-paid),
          method: PayMethod.cash,
          paidOn: today,
          kind: PaymentKind.refund,
          note: reason,
        ),
      );
    }
    await _audit(
      orderId,
      'cancelled',
      '$reason (${advance == CancelAdvance.refund ? 'refunded' : 'kept'})',
    );
  });

  // ---- change log ---------------------------------------------------------

  @override
  Stream<List<AuditEntry>> watchChangeLog(String orderId) =>
      (_db.select(_db.auditLog)
            ..where(
              (t) => t.entity.equals(_entity) & t.entityId.equals(orderId),
            )
            ..orderBy([
              (t) => OrderingTerm.desc(t.at),
              (t) => OrderingTerm.desc(t.id),
            ]))
          .watch()
          .map(
            (rows) => [
              for (final r in rows)
                AuditEntry(
                  at: _time(r.at),
                  action: r.action,
                  detail: r.diffJson,
                ),
            ],
          );

  Future<void> _audit(String orderId, String action, String detail) => _db
      .into(_db.auditLog)
      .insert(
        AuditLogCompanion.insert(
          at: _clock.now().millisecondsSinceEpoch,
          entity: _entity,
          entityId: orderId,
          action: action,
          diffJson: Value(detail),
        ),
      );
}
