// Issue #961 (zik_zak) — the facade-typed span capture a consumer test needs.
//
// #961 retires every direct `package:opentelemetry/` import in the app and its
// tests. The pre-dartastic tests captured spans with the old package's SDK
// pieces (`registerGlobalTracerProvider` + `SimpleSpanProcessor` + an exporter
// reading `ReadOnlySpan`); dartastic keeps those types sealed behind the
// facade — deliberately, so a consumer never imports an OTel package — but
// then a consumer test has NO sanctioned way to boot a recording SDK and read
// the spans its providers stamp. The SpanCaptureAdapter + bootForTesting pair
// is that sanctioned seam: facade-only types, dartastic stays inside.
library;

import 'package:test/test.dart';
import 'package:zuraffa/zuraffa.dart' show SimulationSpanCapture;
import 'package:zuraffa_observability/zuraffa_observability.dart';

void main() {
  group('SpanCaptureAdapter + bootForTesting', () {
    late SpanCaptureAdapter capture;

    setUp(() {
      capture = SpanCaptureAdapter();
    });

    tearDown(() async {
      await OtelTestHarness.teardown();
    });

    test('boot wires the capture into the real SDK pipeline', () async {
      await OtelTestHarness.bootForTesting(capture);

      await OtelTracer.instance.trace(
        'usecase.checkout',
        attributes: Attributes.of({'order.id': 'o-42'}),
        () async {},
      );

      // Give the SimpleSpanProcessor a microtask to export.
      await Future<void>.delayed(Duration.zero);

      expect(capture.hasSpan('usecase.checkout'), isTrue);
      final record = capture.byName('usecase.checkout');
      expect(record, isNotNull);
      expect(record!.attributes['order.id'], 'o-42');
    });

    test('the capture is a SimulationSpanCapture', () {
      // The core seam — the same interface OtelAdapter implements — so a
      // consumer asserts through the one capture vocabulary the fleet knows.
      expect(capture, isA<SimulationSpanCapture>());
    });

    test('reset clears captured spans between scenarios', () async {
      await OtelTestHarness.bootForTesting(capture);

      await OtelTracer.instance.trace('usecase.first', () async {});
      await Future<void>.delayed(Duration.zero);
      expect(capture.hasSpan('usecase.first'), isTrue);

      capture.reset();
      expect(capture.captured, isEmpty);
    });

    test(
      'boot twice without teardown is an error, teardown releases it',
      () async {
        await OtelTestHarness.bootForTesting(capture);
        expect(() => OtelTestHarness.bootForTesting(capture), throwsStateError);

        await OtelTestHarness.teardown();
        // A fresh boot after teardown works (dartastic keeps one global SDK per
        // process; the teardown releases it so the next boot re-initializes).
        // A FRESH capture: the first boot's provider shutdown reached the
        // adapter's own shutdown() (SimpleSpanProcessor shuts its exporter
        // down), so the old instance is retired by design.
        final capture2 = SpanCaptureAdapter();
        await OtelTestHarness.bootForTesting(capture2);
        await OtelTracer.instance.trace('usecase.after', () async {});
        await Future<void>.delayed(Duration.zero);
        expect(capture2.hasSpan('usecase.after'), isTrue);
      },
    );
  });
}
