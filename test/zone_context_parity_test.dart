// Issue #4 — the zone-context parity test the dartastic migration exists for.
//
// The pre-migration base (the Workiva `opentelemetry` re-export shim) activated
// a span by storing it into the Dart **zone**: `contextWithSpan(Context(), span)`
// plus `Context.attach`, read back ambient with `spanFromContext(Context())`.
// Consumers depend on that ambient read — zik_zak calls it inside widget builds
// and nested async closures (listing_sheet, the parsing/scrape providers), never
// passing a span explicitly.
//
// dartastic activates a span differently: `startSpan` does NOT activate, and
// activation is `withSpan` — `Context#run` / `Context#runSync`, which fork a
// zone carrying the context. Same promise, different mechanism. These tests are
// the proof the promise survived the swap:
//
//   1. a span started through [OtelTracer] is retrievable through the facade
//      context accessor inside a nested async execution, with no explicit span
//      passing;
//   2. two concurrent traces never read each other's ambient span (no bleed
//      across zones / missions);
//   3. the synchronous activation path (`traceSync`) behaves the same.
library;

import 'dart:async';

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart' as otel;
import 'package:test/test.dart';
import 'package:zuraffa_observability/zuraffa_observability.dart';

/// What an ambient (no explicit span passing) read sees.
typedef AmbientRead = ({APISpan? span, SpanContext? spanContext, String? name});

/// Reads the ambient span the way a consumer does — no span argument.
AmbientRead _readAmbient() {
  final context = Context.current;
  final span = context.span;
  return (span: span, spanContext: context.spanContext, name: span?.name);
}

/// Two nested async hops before reading — the shape a widget build or a
/// scrape/parsing provider runs in.
Future<AmbientRead> _readAmbientAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  return _readAmbient();
}

void main() {
  group('zone-context parity (dartastic)', () {
    // Activation is an SDK behavior, so the parity tests must run against a
    // live dartastic SDK — the same global provider
    // `OtelFailureReporter.initialize()` installs. The span processor only
    // discards, so nothing here reaches the network.
    setUpAll(() async {
      await otel.OTel.initialize(
        serviceName: 'zone-parity-test',
        endpoint: 'http://127.0.0.1:4318',
        spanProcessor: otel.SimpleSpanProcessor(_DiscardingExporter()),
        enableMetrics: false,
        enableLogs: false,
        detectPlatformResources: false,
      );
    });

    tearDownAll(() async {
      await otel.OTel.reset();
    });

    test('a span started through OtelTracer is readable ambient inside nested '
        'async execution', () async {
      final tracer = OtelTracer.instance;

      AmbientRead? afterFirstHop;
      AmbientRead? afterSecondHop;
      String? spanIdSeenInside;

      await tracer.trace('zone-context.outer', () async {
        spanIdSeenInside = tracer.currentSpanId;
        afterFirstHop = _readAmbient();
        afterSecondHop = await _readAmbientAsync();
      });

      expect(afterFirstHop, isNotNull);
      expect(afterSecondHop, isNotNull);
      // Both reads see the span the tracer started — the span is ambient, so
      // nothing was passed down.
      expect(afterFirstHop!.name, 'zone-context.outer');
      expect(afterSecondHop!.name, 'zone-context.outer');
      expect(afterFirstHop!.spanContext?.spanId.toString(), spanIdSeenInside);
      expect(afterSecondHop!.spanContext?.spanId.toString(), spanIdSeenInside);
      expect(afterSecondHop!.span, isNotNull);
      expect(afterSecondHop!.spanContext?.isValid, isTrue);
    });

    test("two concurrent traces never read each other's ambient span", () async {
      final tracer = OtelTracer.instance;
      final reads = <String, AmbientRead>{};
      final idsSeenInside = <String, String?>{};

      Future<void> mission(String name, int delayMs) =>
          tracer.trace('zone-context.$name', () async {
            await Future<void>.delayed(Duration(milliseconds: delayMs));
            idsSeenInside[name] = tracer.currentSpanId;
            reads[name] = await _readAmbientAsync();
          });

      await Future.wait([mission('alpha', 15), mission('beta', 1)]);

      for (final name in ['alpha', 'beta']) {
        // Each mission reads back its OWN span, by name and by id.
        expect(reads[name]!.name, 'zone-context.$name');
        expect(
          reads[name]!.spanContext?.spanId.toString(),
          idsSeenInside[name],
        );
      }
      expect(
        reads['alpha']!.spanContext?.spanId,
        isNot(reads['beta']!.spanContext?.spanId),
        reason: 'two concurrent traces must not share a span id',
      );
      // Activation is scoped to the zone it was armed in — nothing leaked back
      // into the parent zone.
      expect(_readAmbient().span, isNull);
    });

    test('traceSync activates the span ambiently for synchronous code', () {
      final tracer = OtelTracer.instance;

      AmbientRead? inside;
      String? spanIdSeenInside;

      final result = tracer.traceSync('zone-context.sync', () {
        spanIdSeenInside = tracer.currentSpanId;
        inside = _readAmbient();
        return 42;
      });

      expect(result, 42);
      expect(inside!.name, 'zone-context.sync');
      expect(inside!.spanContext?.spanId.toString(), spanIdSeenInside);
      expect(_readAmbient().span, isNull);
    });
  });
}

/// A span exporter that keeps nothing — the parity tests assert on the
/// ambient context, never on what an exporter received.
class _DiscardingExporter implements otel.SpanExporter {
  @override
  Future<void> export(List<otel.Span> spans) async {}

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {}
}
