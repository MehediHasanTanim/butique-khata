import 'package:drift/drift.dart';

/// A photo attached to something (a garment in an order, a customer, ...).
/// Files live in the app's private media folder, not the phone gallery.
@DataClassName('AttachmentRow')
@TableIndex(name: 'idx_attachment_owner', columns: {#ownerType, #ownerId})
class Attachment extends Table {
  TextColumn get id => text()();

  /// `order_item` | `customer` | `measurement_set`.
  TextColumn get ownerType => text()();
  TextColumn get ownerId => text()();

  /// Paths relative to the media folder.
  TextColumn get path => text()();
  TextColumn get thumbPath => text().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
