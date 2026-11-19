import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart' as otel;
import 'package:zuraffa/zuraffa.dart' show SimulationSpanCapture, SpanSnapshot;

/// Facade-typed span capture for consumer tests (issue
/// [zik_zak#961](https://github.com/arrrrny/zik_zak/issues/961)).
///
/// Implements the REAL production dartastic [otel.SpanExporter] interface —
/// the same interface the live OTLP/HTTP exporter implements — so spans the
/// SDK pipeline produces flow into an in-memory list a test can assert on.
/// Every exposed type is facade-or-core vocabulary ([SpanSnapshot] from core's
/// [SimulationSpanCapture] seam): a consumer test that uses this adapter
/// never imports an OTel package directly.
final class SpanCaptureAdapter
    implements otel.SpanExporter, SimulationSpanCapture {
  final List<SpanSnapshot> _captured = <SpanSnapshot>[];
  bool _shutdown = false;

  /// All captured span records, in export order.
  List<SpanSnapshot> get captured => List.unmodifiable(_captured);

  /// Names of every captured span, in export order.
  List<String> get spanNames => List.unmodifiable(_captured.map((r) => r.name));

  /// The first captured record named [name], or `null`.
  SpanSnapshot? byName(String name) {
    for (final record in _captured) {
      if (record.name == name) return record;
    }
    return null;
  }

  /// Whether a span named [name] was captured.
  bool hasSpan(String name) => byName(name) != null;

  /// Whether [shutdown] was called.
  bool get isShutdown => _shutdown;

  /// Forget everything captured so far (between scenarios).
  void reset() => _captured.clear();

  @override
  Future<void> export(List<otel.Span> spans) async {
    if (_shutdown) return;
    for (final span in spans) {
      final attributes = <String, Object>{};
      for (final attribute in span.attributes.toList()) {
        attributes[attribute.key] = attribute.value;
      }
      _captured.add(
        SpanSnapshot(
          name: span.name,
          status: span.status,
          attributes: attributes,
        ),
      );
    }
  }

  @override
  Future<void> forceFlush() async {
    // In-memory capture: nothing to flush.
  }

  @override
  Future<void> shutdown() async {
    _shutdown = true;
  }
}

/// Boots dartastic's global SDK for a consumer test, recording into
/// [capture].
///
/// dartastic keeps ONE global SDK per process and the facade deliberately
/// seals the SDK boot types ([otel.SpanProcessor] and friends), so a consumer
/// test cannot wire a capture without importing an OTel package — which the
/// sealed facade exists to make unnecessary. This harness is the sanctioned
/// seam: the dartastic types stay inside this package.
///
/// ```dart
/// final capture = SpanCaptureAdapter();
/// await OtelTestHarness.bootForTesting(capture);
/// await OtelTracer.instance.trace('parsing.parse', () async { ... });
/// expect(capture.byName('parsing.parse'), isNotNull);
/// await OtelTestHarness.teardown();
/// ```
///
/// Boot twice without [teardown] throws (dartastic's own single-init
/// contract); [teardown] releases the global SDK so the next boot
/// re-initializes.
abstract final class OtelTestHarness {
  static bool _booted = false;

  /// Whether the harness currently holds a live global SDK.
  static bool get booted => _booted;

  /// Initializes the dartastic SDK with a [otel.SimpleSpanProcessor] that
  /// exports into [capture]. Metrics and logs stay off — the package owns
  /// its own log pipeline and never exported metrics.
  static Future<void> bootForTesting(SpanCaptureAdapter capture) async {
    if (_booted) {
      throw StateError(
        'OtelTestHarness is already booted — call OtelTestHarness.teardown() '
        'first (dartastic keeps one global SDK per process).',
      );
    }
    await otel.OTel.initialize(
      serviceName: 'harness-test',
      endpoint: 'http://127.0.0.1:4318',
      spanProcessor: otel.SimpleSpanProcessor(capture),
      enableMetrics: false,
      enableLogs: false,
      detectPlatformResources: false,
    );
    _booted = true;
  }

  /// Releases the global SDK so the next [bootForTesting] re-initializes.
  ///
  /// Safe to call when not booted (a no-op) so a `tearDown` can run it
  /// unconditionally after a test that never booted.
  static Future<void> teardown() async {
    if (!_booted) return;
    // `OTel.reset` is @visibleForTesting and this harness is exactly that
    // test support; the suppress comment must sit directly above the call.
    // ignore: invalid_use_of_visible_for_testing_member
    await otel.OTel.reset();
    _booted = false;
  }
}
