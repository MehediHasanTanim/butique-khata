/// A domain-level failure that the UI can present without a stack trace.
class Failure implements Exception {
  const Failure(this.code, [this.message]);

  /// Stable machine-readable code, e.g. `db.wrong_key`; also the l10n key base.
  final String code;
  final String? message;

  @override
  String toString() =>
      message == null ? 'Failure($code)' : 'Failure($code: $message)';
}

/// Outcome of an operation that can fail for expected reasons.
sealed class Result<T> {
  const Result();

  const factory Result.ok(T value) = Ok<T>;
  const factory Result.err(Failure failure) = Err<T>;

  bool get isOk => this is Ok<T>;

  T? get valueOrNull => switch (this) {
    Ok<T>(:final value) => value,
    Err<T>() => null,
  };

  Failure? get failureOrNull => switch (this) {
    Ok<T>() => null,
    Err<T>(:final failure) => failure,
  };

  R when<R>({
    required R Function(T value) ok,
    required R Function(Failure failure) err,
  }) => switch (this) {
    Ok<T>(:final value) => ok(value),
    Err<T>(:final failure) => err(failure),
  };

  Result<R> map<R>(R Function(T value) transform) => switch (this) {
    Ok<T>(:final value) => Result.ok(transform(value)),
    Err<T>(:final failure) => Result.err(failure),
  };
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.failure);
  final Failure failure;
}
