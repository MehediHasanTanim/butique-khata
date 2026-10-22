import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:tailor_khata/core/db/app_database.dart';
import 'package:tailor_khata/core/ids/id_generator.dart';
import 'package:tailor_khata/core/money/money.dart';
import 'package:tailor_khata/core/time/clock.dart';
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
            createdAt: now,
            updatedAt: now,
          ),
        );
    await _db.batch((batch) {
      batch.insertAll(_db.orderItem, [
        for (final item in input.items)
          OrderItemCompanion.insert(
            id: _ids.newId(),
            orderId: orderId,
            garmentTypeId: item.garmentTypeId,
            qty: Value(item.qty),
            price: item.price.poisha,
            measurementSetId: Value(item.measurementSetId),
            fabricSource: Value(item.fabricSource?.dbValue),
            colour: Value(item.colour),
            styleJson: Value(
              item.style.isEmpty ? null : jsonEncode(item.style),
            ),
            note: Value(item.note),
            status: OrderStatus.received.dbValue,
            statusChangedAt: now,
            workUnits: Value(item.workUnits * item.qty),
          ),
      ]);
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
    return _db
        .customSelect(
          'SELECT o.*, c.name AS customer_name, m.total AS total, '
          'm.paid AS paid, '
          '(SELECT COUNT(*) FROM order_item i WHERE i.order_id = o.id) '
          'AS item_count '
          'FROM customer_order o '
          'JOIN customer c ON c.id = o.customer_id '
          'JOIN v_order_money m ON m.order_id = o.id '
          'WHERE ${where.join(' AND ')} '
          'ORDER BY o.delivery_date ASC, o.number ASC',
          variables: vars,
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
              OrderSummary(
                order: _order(_db.customerOrder.map(r.data)),
                customerName: r.read<String>('customer_name'),
                itemCount: r.read<int>('item_count'),
                money: OrderMoney(
                  total: Money(r.read<int>('total')),
                  paid: Money(r.read<int>('paid')),
                ),
              ),
          ],
        );
  }

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
  Future<void> setItemStatus(String itemId, OrderStatus to) =>
      _db.transaction(() async {
        final item = await (_db.select(
          _db.orderItem,
        )..where((t) => t.id.equals(itemId))).getSingle();
        await _requireOpen(item.orderId);
        final from = OrderStatus.fromDb(item.status);
        if (!from.canMoveTo(to)) {
          throw StateError('Cannot move item from $from to $to');
        }
        await _moveItem(item, to);
        await _rollUp(item.orderId);
      });

  @override
  Future<void> setAllItemsStatus(String orderId, OrderStatus to) =>
      _db.transaction(() async {
        await _requireOpen(orderId);
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
    await _audit(orderId, 'details_changed', changes.join('; '));
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
