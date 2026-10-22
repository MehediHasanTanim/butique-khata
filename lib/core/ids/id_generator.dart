import 'package:uuid/uuid.dart';

/// Source of primary keys. UUIDv7 is time-ordered and collision-safe across
/// devices, which keeps future sync possible (TD §4.1).
abstract class IdGenerator {
  String newId();
}

class UuidV7Generator implements IdGenerator {
  const UuidV7Generator();

  static const Uuid _uuid = Uuid();

  @override
  String newId() => _uuid.v7();
}

/// Predictable ids for tests: `id-1`, `id-2`, ...
class SequentialIdGenerator implements IdGenerator {
  SequentialIdGenerator([this.prefix = 'id']);

  final String prefix;
  int _next = 1;

  @override
  String newId() => '$prefix-${_next++}';
}
