import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart'
    show OTel, SimpleSpanProcessor, SpanExporter;

/// Boots the dartastic SDK with [exporter] as the only span processor, so a
/// test can capture every ended span in-memory and assert on it.
///
/// This is the **sealed test seam** of the observability companion: a
/// consumer that needs to assert on span names / attributes / status no
/// longer imports `dartastic_opentelemetry` (or the old `opentelemetry`)
/// directly — it builds its own [SpanExporter], hands it here, and reads the
/// captured spans back.
///
/// The SDK is a process-wide singleton in dartastic; a second call returns
/// the same exporter (the first registration wins, exactly as the old
/// `registerGlobalTracerProvider` refused to replace a registered provider).
/// Call [OTel.reset] between test files in the same process if a fresh
/// provider is required.
///
/// Metrics and logs stay off — the observability package owns its own log
/// pipeline, and never exported metrics — so only traces are captured.
Future<void> initializeOtelForCapture(SpanExporter exporter) {
  return OTel.initialize(
    serviceName: 'zikzak-test',
    endpoint: 'http://localhost:4318',
    spanProcessor: SimpleSpanProcessor(exporter),
    enableMetrics: false,
    enableLogs: false,
    detectPlatformResources: false,
  );
}