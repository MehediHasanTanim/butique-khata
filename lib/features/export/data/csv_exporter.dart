import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:tailor_khata/core/db/app_database.dart';

/// Writes the shop's records as CSV files in one zip (B-4), for a
/// spreadsheet or an accountant. Read-only: nothing is changed.
class CsvExporter {
  CsvExporter(this._db);

  final AppDatabase _db;

  static const List<String> fileNames = [
    'customers.csv',
    'orders.csv',
    'payments.csv',
    'measurements.csv',
  ];

  /// A zip with [fileNames]. Each file starts with a UTF-8 byte-order mark so
  /// Excel shows Bangla names correctly.
  Future<Uint8List> buildZip() async {
    final contents = {
      'customers.csv': await customers(),
      'orders.csv': await orders(),
      'payments.csv': await payments(),
      'measurements.csv': await measurements(),
    };
    final archive = Archive();
    for (final entry in contents.entries) {
      archive.add(
        ArchiveFile.bytes(entry.key, [
          0xEF,
          0xBB,
          0xBF,
          ...utf8.encode(entry.value),
        ]),
      );
    }
    return ZipEncoder().encodeBytes(archive);
  }

  Future<String> customers() => _table(
    'SELECT id, name, phone, address, note, created_at, deleted_at '
    'FROM customer ORDER BY name_norm, id',
    const {
      'id': 'id',
      'name': 'name',
      'phone': 'phone',
      'address': 'address',
      'note': 'note',
      'created_at': 'created',
      'deleted_at': 'deleted',
    },
    dates: const {'created_at', 'deleted_at'},
  );

  Future<String> orders() => _table(
    'SELECT o.number, c.name AS customer, c.phone, o.delivery_date, '
    'o.trial_date, o.status, o.urgent, '
    'COALESCE((SELECT SUM(i.price) FROM order_item i WHERE i.order_id = o.id), 0) '
    'AS items_total, o.discount, m.total, m.paid, m.total - m.paid AS due, '
    'o.cancelled_at, o.cancel_reason, o.note, o.created_at '
    'FROM customer_order o JOIN customer c ON c.id = o.customer_id '
    'JOIN v_order_money m ON m.order_id = o.id '
    'WHERE o.deleted_at IS NULL ORDER BY o.number',
    const {
      'number': 'order_no',
      'customer': 'customer',
      'phone': 'phone',
      'delivery_date': 'delivery_date',
      'trial_date': 'trial_date',
      'status': 'status',
      'urgent': 'urgent',
      'items_total': 'items_total_bdt',
      'discount': 'discount_bdt',
      'total': 'total_bdt',
      'paid': 'paid_bdt',
      'due': 'due_bdt',
      'cancelled_at': 'cancelled',
      'cancel_reason': 'cancel_reason',
      'note': 'note',
      'created_at': 'created',
    },
    money: const {'items_total', 'discount', 'total', 'paid', 'due'},
    dates: const {'cancelled_at', 'created_at'},
    flags: const {'urgent'},
  );

  Future<String> payments() => _table(
    'SELECT o.number, c.name AS customer, p.paid_on, p.amount, p.kind, '
    'p.method, p.note FROM payment p '
    'JOIN customer_order o ON o.id = p.order_id '
    'JOIN customer c ON c.id = o.customer_id '
    'ORDER BY p.paid_on, o.number, p.created_at, p.id',
    const {
      'number': 'order_no',
      'customer': 'customer',
      'paid_on': 'date',
      'amount': 'amount_bdt',
      'kind': 'kind',
      'method': 'method',
      'note': 'note',
    },
    money: const {'amount'},
  );

  /// One row per measured value, every version (history is the point).
  Future<String> measurements() => _table(
    'SELECT c.name AS customer, c.phone, g.key AS garment, s.version, '
    's.taken_on, s.status, s.note AS set_note, v.field_key, v.mm10, '
    'v.text_value FROM measurement_set s '
    'JOIN customer c ON c.id = s.customer_id '
    'JOIN garment_type g ON g.id = s.garment_type_id '
    'JOIN measurement_value v ON v.set_id = s.id '
    'ORDER BY c.name_norm, c.id, g.key, s.version, v.field_key',
    const {
      'customer': 'customer',
      'phone': 'phone',
      'garment': 'garment',
      'version': 'version',
      'taken_on': 'taken_on',
      'status': 'status',
      'set_note': 'set_note',
      'field_key': 'field',
      'mm10': 'inches',
      'text_value': 'text',
    },
    inches: const {'mm10'},
    extraCm: 'mm10',
  );

  /// Runs [sql] and renders the rows. [headers] maps result columns to the
  /// header text, in order.
  Future<String> _table(
    String sql,
    Map<String, String> headers, {
    Set<String> money = const {},
    Set<String> dates = const {},
    Set<String> flags = const {},
    Set<String> inches = const {},
    String? extraCm,
  }) async {
    final rows = await _db.customSelect(sql).get();
    final out = StringBuffer();
    final head = [...headers.values, if (extraCm != null) 'cm'];
    out.write('${head.map(csvCell).join(',')}\r\n');
    for (final row in rows) {
      final cells = <String>[];
      for (final column in headers.keys) {
        final value = row.data[column];
        cells.add(
          csvCell(
            value == null
                ? ''
                : money.contains(column)
                ? formatTaka(value as int)
                : dates.contains(column)
                ? isoDate(value as int)
                : flags.contains(column)
                ? ((value as int) == 0 ? 'no' : 'yes')
                : inches.contains(column)
                ? ((value as int) / 254).toStringAsFixed(3)
                : '$value',
          ),
        );
      }
      if (extraCm != null) {
        final v = row.data[extraCm];
        cells.add(v == null ? '' : ((v as int) / 100).toStringAsFixed(1));
      }
      out.write('${cells.join(',')}\r\n');
    }
    return out.toString();
  }

  /// Poisha as taka with two decimals, e.g. `1250.50`.
  static String formatTaka(int poisha) {
    final sign = poisha < 0 ? '-' : '';
    final abs = poisha.abs();
    return '$sign${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
  }

  static String isoDate(int millis) {
    final d = DateTime.fromMillisecondsSinceEpoch(millis);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  /// One CSV cell: quoted when needed, and defanged if a spreadsheet could
  /// run it as a formula (a customer named `=HYPERLINK(...)`).
  static String csvCell(String value) {
    var text = value;
    if (_looksLikeFormula(text)) text = "'$text";
    if (text.contains(RegExp('[",\r\n]'))) {
      text = '"${text.replaceAll('"', '""')}"';
    }
    return text;
  }

  static bool _looksLikeFormula(String text) {
    if (text.isEmpty) return false;
    final first = text[0];
    if (first == '=' || first == '@' || first == '\t' || first == '\r') {
      return true;
    }
    // Phone numbers (+8801...) and negative amounts are fine; "+cmd" is not.
    if (first == '+' || first == '-') {
      return text.length > 1 && !RegExp(r'^[+-][0-9.]').hasMatch(text);
    }
    return false;
  }
}
