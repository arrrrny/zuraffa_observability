// PR #6 review fix: the sealed test-capture seam shipped untested — nothing
// in the suite called `initializeOtelForCapture` (otel_adapter_test boots the
// SDK through its own private `boot()` helper), so a wiring typo in the seam
// would pass the whole suite green. This file is the minimal seam coverage:
// boot through the seam, prove the consumer-built exporter receives spans,
// and pin both documented contracts — the serviceName override lands in the
// service.name resource attribute, and a second call in one process throws.
library;

import 'package:test/test.dart';
import 'package:zuraffa_observability/zuraffa_observability.dart';

void main() {
  group('initializeOtelForCapture (sealed test seam)', () {
    late OtelAdapter adapter;

    setUp(() async {
      adapter = OtelAdapter();
      // dartastic keeps one global SDK: reset between tests so each one boots
      // its own provider with a fresh capture.
      await OTel.reset();
    });

    tearDown(() async {
      await OTel.reset();
    });

    test('a consumer-built exporter receives spans through the seam',
        () async {
      await initializeOtelForCapture(adapter);
      OTel.tracer().startSpan('seam.span').end();

      // Give the SimpleSpanProcessor a microtask to export.
      await Future<void>.delayed(Duration.zero);

      expect(adapter.spanNames, contains('seam.span'));
    });

    test('serviceName pins the service.name resource attribute', () async {
      await initializeOtelForCapture(adapter, serviceName: 'seam-test');

      final resource = OTel.defaultResource;
      final attributes = <String, Object>{
        for (final attribute in resource!.attributes.toList())
          attribute.key: attribute.value,
      };
      expect(attributes['service.name'], 'seam-test');
    });

    test('a second call in the same process throws (dartastic contract)',
        () async {
      await initializeOtelForCapture(adapter);
      // dartastic refuses to replace a registered provider with a StateError
      // — the seam forwards that contract, it does not swallow it.
      await expectLater(
        initializeOtelForCapture(OtelAdapter()),
        throwsStateError,
      );
    });
  });
}
