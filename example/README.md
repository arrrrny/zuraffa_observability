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

```dart
import 'package:zuraffa_observability/zuraffa_observability.dart';

void main() {
  ZuraffaObservability.installGlobalErrorCapture(
    reportUncaughtAsSpan: true,
  );
  runApp();
}
```