/// Raw SQL that Drift's table DSL cannot express: full-text search and the
/// append-only guards on measurement history (TD §5.1, §7.1).
class SchemaExtras {
  const SchemaExtras._();

  /// Statements applied when schema v2 is created or migrated to.
  static const List<String> v2 = [..._fts, ..._appendOnly];

  /// Statements applied when schema v3 is created or migrated to.
  static const List<String> v3 = [
    // Total / paid per order. Due = total - paid is derived here, never
    // stored, so it cannot drift out of sync with payments (TD §4.3).
    '''
CREATE VIEW IF NOT EXISTS v_order_money AS
SELECT o.id AS order_id,
       COALESCE((SELECT SUM(i.price) FROM order_item i WHERE i.order_id = o.id), 0)
         - o.discount AS total,
       COALESCE((SELECT SUM(p.amount) FROM payment p WHERE p.order_id = o.id), 0)
         AS paid
FROM customer_order o''',
    // Payments are immutable: corrections are new rows.
    '''
CREATE TRIGGER IF NOT EXISTS trg_payment_no_update BEFORE UPDATE ON payment
BEGIN SELECT RAISE(ABORT, 'payment is immutable'); END''',
    '''
CREATE TRIGGER IF NOT EXISTS trg_payment_no_delete BEFORE DELETE ON payment
BEGIN SELECT RAISE(ABORT, 'payment is immutable'); END''',
  ];

  static const List<String> _fts = [
    // `categories` includes M* so Bangla vowel signs stay inside a token.
    '''
CREATE VIRTUAL TABLE IF NOT EXISTS customer_fts USING fts5(
  name_norm, phone_digits,
  content='customer', content_rowid='rowid',
  tokenize = "unicode61 remove_diacritics 0 categories 'L* N* Co M*'"
)''',
    '''
CREATE TRIGGER IF NOT EXISTS customer_fts_ai AFTER INSERT ON customer BEGIN
  INSERT INTO customer_fts(rowid, name_norm, phone_digits)
  VALUES (new.rowid, new.name_norm, new.phone_digits);
END''',
    '''
CREATE TRIGGER IF NOT EXISTS customer_fts_ad AFTER DELETE ON customer BEGIN
  INSERT INTO customer_fts(customer_fts, rowid, name_norm, phone_digits)
  VALUES ('delete', old.rowid, old.name_norm, old.phone_digits);
END''',
    '''
CREATE TRIGGER IF NOT EXISTS customer_fts_au AFTER UPDATE ON customer BEGIN
  INSERT INTO customer_fts(customer_fts, rowid, name_norm, phone_digits)
  VALUES ('delete', old.rowid, old.name_norm, old.phone_digits);
  INSERT INTO customer_fts(rowid, name_norm, phone_digits)
  VALUES (new.rowid, new.name_norm, new.phone_digits);
END''',
  ];

  static const List<String> _appendOnly = [
    '''
CREATE TRIGGER IF NOT EXISTS trg_mvalue_no_update BEFORE UPDATE ON measurement_value
BEGIN SELECT RAISE(ABORT, 'measurement_value is append-only'); END''',
    '''
CREATE TRIGGER IF NOT EXISTS trg_mvalue_no_delete BEFORE DELETE ON measurement_value
BEGIN SELECT RAISE(ABORT, 'measurement_value is append-only'); END''',
    '''
CREATE TRIGGER IF NOT EXISTS trg_mset_no_delete BEFORE DELETE ON measurement_set
BEGIN SELECT RAISE(ABORT, 'measurement_set is append-only'); END''',
    // Only status and fit_outcome may change after insert.
    '''
CREATE TRIGGER IF NOT EXISTS trg_mset_limited_update BEFORE UPDATE ON measurement_set
WHEN old.id IS NOT new.id
  OR old.customer_id IS NOT new.customer_id
  OR old.garment_type_id IS NOT new.garment_type_id
  OR old.version IS NOT new.version
  OR old.taken_on IS NOT new.taken_on
  OR old.taken_by IS NOT new.taken_by
  OR old.note IS NOT new.note
  OR old.display_unit IS NOT new.display_unit
  OR old.supersedes_id IS NOT new.supersedes_id
  OR old.created_at IS NOT new.created_at
BEGIN SELECT RAISE(ABORT, 'measurement_set is append-only'); END''',
  ];
}
