# zuraffa_observability

OpenTelemetry-based tracing, failure reporting and telemetry hooks for Zuraffa
apps. The OTel base is `dartastic_opentelemetry`; the span/attribute/context
value types are re-exported from this package so you never import an OTel
package directly.

## Enable OTLP reporting

```dart
import 'package:zuraffa_observability/zuraffa_observability.dart';

Future<void> main() async {
  await enableOtelReporting(
    endpoint: 'http://localhost:4318',
    serviceName: 'my-service',
  );

  final tracer = OtelTracer.instance;
  final span = tracer.startSpan('checkout');
  try {
    // ... do work ...
  } finally {
    span.end();
  }
}
```

## Capture a span in a test

```dart
import 'package:zuraffa_observability/zuraffa_observability.dart';

void main() {
  initializeOtelForCapture();
  // run code under test, then assert on the captured SimulationSpanCapture.
}
```

## Report uncaught errors as spans

Fork the guarded capture zone **before** the Flutter binding is first touched,
then run the whole boot inside it. `installGlobalErrorCapture()` records the
zone it returns, and `runApp` must mount in that same zone:

```dart
import 'package:flutter/widgets.dart';
import 'package:zuraffa_observability/zuraffa_observability.dart';

Future<void> main() async {
  // Fork FIRST — ahead of any ensureInitialized (explicit, or implicit via
  // dotenv.load() / Hive.initFlutter()), so the binding is created inside the
  // zone `runApp` will run in.
  final captureZone = await ZuraffaObservability.installGlobalErrorCapture(
    reportUncaughtAsSpan: true,
  );

  await captureZone.run(() async {
    WidgetsFlutterBinding.ensureInitialized(); // idempotent; inside the zone
    runApp(const MyApp());
  });
}
```

> **Binding-zone ordering rule:** the Flutter binding must be initialized
> inside the zone `runApp` runs in. `ensureInitialized()` records `Zone.current`
> (`BindingBase._debugBindingZone`) and `runApp` (via `_runWidget`) asserts
> against it; calling
> `ensureInitialized()` in the root zone and then mounting in the capture zone
> yields `Zone mismatch.` per boot (debug-only, routed as a `failure.*` span —
> the failure behind zik_zak#1031). Keep `ensureInitialized()` — and every other
> binding touch — inside the guarded zone.