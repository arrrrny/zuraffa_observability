import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart' as otel;
import 'package:zuraffa/zuraffa.dart' show SimulationSpanCapture, SpanSnapshot;

/// Certified OpenTelemetry simulation: a capture-and-assert exporter.
///
/// Implements the REAL production dartastic [otel.SpanExporter] interface — the
/// same interface the live OTLP/HTTP exporter implements — so
/// `TelemetryHook`/`OtelTracer` pipelines run unchanged against it and
/// every span ends up asserted from memory instead of shipped over the
/// network. Moved here from the core simulation module by
/// spec 1653-trim-heavy-deps (issue #1661): core consumes the light
/// [SimulationSpanCapture] seam, the vendor-typed exporter lives here.
final class OtelAdapter implements otel.SpanExporter, SimulationSpanCapture {
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
