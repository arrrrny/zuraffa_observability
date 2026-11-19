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
/// The SDK is a process-wide singleton in dartastic; a second call **throws**
/// — dartastic's `OTel.initialize` refuses to replace a registered provider
/// (`OTel.initialize() can only be called once`, a `StateError`). Never rely
/// on a second call being a no-op: call [OTel.reset] before re-initializing
/// (e.g. in `setUp`).
///
/// [serviceName] and [endpoint] default to `null`, which defers to the
/// dartastic defaults and the `OTEL_SERVICE_NAME` /
/// `OTEL_EXPORTER_OTLP_ENDPOINT` environment variables (an explicit argument
/// outranks the environment, so pass one only when you want to pin it). The
/// service name flows into the `service.name` resource attribute of every
/// captured span, so assertions on that attribute run against whatever the
/// process resolved here — pass [serviceName] explicitly to pin it.
///
/// Metrics and logs stay off — the observability package owns its own log
/// pipeline, and never exported metrics — so only traces are captured.
Future<void> initializeOtelForCapture(
  SpanExporter exporter, {
  String? serviceName,
  String? endpoint,
}) {
  return OTel.initialize(
    serviceName: serviceName,
    endpoint: endpoint,
    spanProcessor: SimpleSpanProcessor(exporter),
    enableMetrics: false,
    enableLogs: false,
    detectPlatformResources: false,
  );
}
