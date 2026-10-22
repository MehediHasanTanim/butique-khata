/// Result of timing one operation.
class PerfSample {
  const PerfSample(this.label, this.elapsed);

  final String label;
  final Duration elapsed;

  @override
  String toString() => '$label: ${elapsed.inMilliseconds} ms';
}

/// Minimal stopwatch harness used to record baselines (cold start, search
/// latency) and, later, to fail CI on regressions (TD §11).
class PerfHarness {
  final List<PerfSample> samples = [];

  Future<T> measure<T>(String label, Future<T> Function() action) async {
    final watch = Stopwatch()..start();
    try {
      return await action();
    } finally {
      watch.stop();
      samples.add(PerfSample(label, watch.elapsed));
    }
  }

  T measureSync<T>(String label, T Function() action) {
    final watch = Stopwatch()..start();
    try {
      return action();
    } finally {
      watch.stop();
      samples.add(PerfSample(label, watch.elapsed));
    }
  }
}
