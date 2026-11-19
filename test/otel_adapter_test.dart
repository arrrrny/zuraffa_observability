// Spec 1653-trim-heavy-deps (issue #1661): the OtelAdapter tests moved
// with the adapter from the core simulation suite to the observability
// companion (the vendor-typed exporter lives here; core consumes the
// light SimulationSpanCapture seam).
//
// Issue #4: the adapter now implements dartastic's SpanExporter, and these
// tests pin the SpanSnapshot shape (name, status, attributes) the simulation
// certification asserts on — the same shape the pre-dartastic pipeline
// produced.
library;

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart' as otel;
import 'package:test/test.dart';
import 'package:zuraffa_observability/zuraffa_observability.dart';

void main() {
  group('OtelAdapter (capture-and-assert exporter)', () {
    late OtelAdapter adapter;

    setUp(() async {
      adapter = OtelAdapter();
      // dartastic keeps one global SDK: reset between tests so each one boots
      // its own provider with a fresh capture.
      await otel.OTel.reset();
    });

    tearDown(() async {
      await otel.OTel.reset();
    });

    /// Boots the dartastic SDK with [adapter] as the only span processor.
    Future<void> boot() => otel.OTel.initialize(
      serviceName: 'simulation-test',
      endpoint: 'http://localhost:4318',
      spanProcessor: otel.SimpleSpanProcessor(adapter),
      enableMetrics: false,
      enableLogs: false,
      detectPlatformResources: false,
    );

    test('captures spans produced through the real SDK pipeline', () async {
      await boot();
      final tracer = otel.OTel.tracer();
      final span = tracer.startSpan(
        'usecase.PlaceOrder',
        attributes: otel.Attributes.of(<String, Object>{'order.id': 'o-42'}),
      );
      span.end();

      // Give the SimpleSpanProcessor a microtask to export.
      await Future<void>.delayed(Duration.zero);

      expect(adapter.spanNames, contains('usecase.PlaceOrder'));
      final record = adapter.byName('usecase.PlaceOrder');
      expect(record, isNotNull);
      expect(record!.attributes['order.id'], 'o-42');
      expect(adapter.hasSpan('usecase.PlaceOrder'), isTrue);
      expect(adapter.hasSpan('usecase.NeverRan'), isFalse);
    });

    test('capture-and-assert: ended spans report their status', () async {
      await boot();
      final tracer = otel.OTel.tracer();
      tracer.startSpan('usecase.Healthy').end();
      final failing = tracer.startSpan('usecase.Broken');
      failing.setStatus(otel.SpanStatusCode.Error, 'boom');
      failing.end();
      await Future<void>.delayed(Duration.zero);

      final healthy = adapter.byName('usecase.Healthy');
      final broken = adapter.byName('usecase.Broken');
      expect(healthy, isNotNull);
      expect(broken, isNotNull);
      expect(healthy!.status, otel.SpanStatusCode.Unset);
      expect(broken!.status, otel.SpanStatusCode.Error);
    });

    test('implements the production SpanExporter interface', () async {
      final exporter = OtelAdapter();
      // Same production interface the OTLP collector exporter implements.
      expect(exporter, isA<otel.SpanExporter>());
      await exporter.forceFlush();
      await exporter.shutdown();
      expect(exporter.isShutdown, isTrue);
    });
  });
}
