import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart'
    show
        APITracer,
        APITracerProvider,
        Attributes,
        BatchSpanProcessor,
        OtlpHttpExporterConfig,
        OtlpHttpSpanExporter,
        OTel,
        SpanStatusCode,
        TracerProvider;

import 'otel_tracer.dart';

import 'package:zuraffa/zuraffa.dart';

/// OpenTelemetry failure reporter — shipped opinionated with Zuraffa.
///
/// Maps each [AppFailure] to an OTel Span with error status and enriched
/// attributes. Uses dartastic's [BatchSpanProcessor] + [OtlpHttpSpanExporter]
/// for efficient delivery to any OTLP-compatible collector over OTLP/HTTP.
///
/// ## Usage
/// ```dart
/// Zuraffa.addFailureReporter(
///   OtelFailureReporter(
///     collectorEndpoint: Uri.parse('https://otel.mybackend.com/v1/traces'),
///     serviceName: 'my_app',
///   ),
/// );
/// ```
///
/// ## Attributes
/// Each span includes:
/// - `failure.type`: The runtime type of the failure (e.g., `ServerFailure`)
/// - `failure.message`: The failure message
/// - `failure.cause`: The original cause (if any)
/// - Custom attributes from the [FailureReport]
/// - Failure-specific attributes (e.g., `http.status_code` for ServerFailure)
class OtelFailureReporter extends FailureReporter {
  /// The OTLP collector endpoint (e.g., `https://otel.example.com/v1/traces`).
  final Uri collectorEndpoint;

  /// The service name to identify this application in traces.
  final String serviceName;

  /// Optional API key for authentication (sent as Bearer token).
  final String? apiKey;

  /// Optional instrumentation name (defaults to `zuraffa-failure-reporter`).
  final String instrumentationName;

  late final APITracer _tracer;

  @override
  String get id => 'zuraffa-otel';

  /// The [OtelTracer] instance used to expose active span context to
  /// [ArtifactPublisher] for cross-referencing artifacts with traces.
  ///
  /// Populated during [initialize] so that `ArtifactPublisher.spanContextProvider`
  /// can capture the active trace/span IDs when an artifact is published.
  OtelTracer get tracer => OtelTracer.instance;

  OtelFailureReporter({
    required this.collectorEndpoint,
    required this.serviceName,
    this.apiKey,
    this.instrumentationName = 'zuraffa-failure-reporter',
  });

  @override
  Future<void> initialize() async {
    final Map<String, String> headers = apiKey != null
        ? {'Authorization': 'Bearer $apiKey'}
        : <String, String>{};

    final endpoint = collectorEndpoint.toString();

    // dartastic's equivalent of the old
    // `TracerProviderBase(resource:, processors: [BatchSpanProcessor(...)])` +
    // `registerGlobalTracerProvider`: OTel.initialize installs the global SDK
    // provider, and the OTLP/HTTP exporter carries the collector endpoint and
    // auth header over unchanged (the exporter appends `/v1/traces` itself when
    // the endpoint does not already end with it).
    //
    // Metrics and logs stay off: this package owns its own log pipeline
    // (OtelLogExporter) and never exported metrics, so dartastic must not
    // configure either (issue #4 — out of scope).
    try {
      await OTel.initialize(
        endpoint: endpoint,
        serviceName: serviceName,
        spanProcessor: BatchSpanProcessor(
          OtlpHttpSpanExporter(
            OtlpHttpExporterConfig(endpoint: endpoint, headers: headers),
          ),
        ),
        enableMetrics: false,
        enableLogs: false,
        // Keep the resource to `service.name` (+ service.version), the way the
        // pre-dartastic provider did, instead of merging host/arch detection.
        detectPlatformResources: false,
      );
    } on StateError {
      // Already initialized — reuse the existing global provider.
      // This happens when multiple OtelFailureReporters are created
      // (e.g., in tests) or when the app re-initializes.
    }
    _tracer = _globalTracerProvider().getTracer(instrumentationName);

    // Wire OtelTracer's active span context into ArtifactPublisher so that
    // every published artifact is automatically stamped with trace_id/span_id.
    OtelTracer.instance.instrumentationName = instrumentationName;
    ArtifactPublisher.instance.spanContextProvider = () => (
      traceId: OtelTracer.instance.currentTraceId,
      spanId: OtelTracer.instance.currentSpanId,
    );
  }

  @override
  Future<void> reportBatch(List<FailureReport> reports) async {
    for (final report in reports) {
      final span = _tracer.startSpan('failure.${report.failure.runtimeType}');

      try {
        // Set error status
        span.setStatus(SpanStatusCode.Error, report.failure.message);

        // Core attributes
        span.addAttributes(
          Attributes.of(<String, Object>{
            'failure.type': report.failure.runtimeType.toString(),
            'failure.message': report.failure.message,
            'failure.timestamp': report.timestamp.toIso8601String(),
          }),
        );

        if (report.failure.cause != null) {
          span.addAttributes(
            Attributes.of(<String, Object>{
              'failure.cause': report.failure.cause.toString(),
            }),
          );
        }

        // Failure-specific attributes
        _addFailureAttributes(span, report.failure);

        // User-provided attributes
        if (report.attributes != null) {
          span.addAttributes(
            Attributes.of(
              report.attributes!.map(
                (key, value) => MapEntry<String, Object>(key, value.toString()),
              ),
            ),
          );
        }

        // If a companion artifact was published for this failure, record it
        // as a span event so the trace links forward to artifact storage.
        // The artifact carries trace_id/span_id metadata so you can also
        // navigate backward from storage to this span.
        final artifactId = report.attributes?['artifactId'];
        if (artifactId != null && artifactId.isNotEmpty) {
          span.addEventNow(
            'artifact.published',
            Attributes.of(<String, Object>{'artifact.id': artifactId}),
          );
        }

        // Record exception with stack trace. Prefer the report-level stack
        // trace, but fall back to the one carried on the failure itself so a
        // caller that only set `UnknownFailure.from(error, stackTrace)` still
        // gets the span enriched (the capture path passes it there, not on the
        // report).
        final st = report.stackTrace ?? report.failure.stackTrace;
        if (st != null) {
          span.recordException(report.failure, stackTrace: st);
        }
      } finally {
        span.end();
      }
    }
  }

  /// Add failure-type-specific attributes to the span.
  void _addFailureAttributes(dynamic span, AppFailure failure) {
    void add(Map<String, Object> attributes) =>
        span.addAttributes(Attributes.of(attributes));

    switch (failure) {
      case ServerFailure(:final statusCode):
        if (statusCode != null) {
          add(<String, Object>{'http.status_code': statusCode});
        }
      case NetworkFailure():
        add(<String, Object>{'failure.category': 'network'});
      case ValidationFailure(:final fieldErrors):
        add(<String, Object>{'failure.category': 'validation'});
        if (fieldErrors != null) {
          add(<String, Object>{'failure.fields': fieldErrors.keys.join(',')});
        }
      case NotFoundFailure(:final resourceType, :final resourceId):
        add(<String, Object>{'failure.category': 'not_found'});
        if (resourceType != null) {
          add(<String, Object>{'failure.resource_type': resourceType});
        }
        if (resourceId != null) {
          add(<String, Object>{'failure.resource_id': resourceId});
        }
      case UnauthorizedFailure():
        add(<String, Object>{
          'failure.category': 'auth',
          'failure.auth_type': 'unauthorized',
        });
      case ForbiddenFailure(:final requiredPermission):
        add(<String, Object>{
          'failure.category': 'auth',
          'failure.auth_type': 'forbidden',
        });
        if (requiredPermission != null) {
          add(<String, Object>{
            'failure.required_permission': requiredPermission,
          });
        }
      case TimeoutFailure(:final timeout):
        add(<String, Object>{'failure.category': 'timeout'});
        if (timeout != null) {
          add(<String, Object>{'failure.timeout_ms': timeout.inMilliseconds});
        }
      case ConflictFailure(:final conflictType):
        add(<String, Object>{'failure.category': 'conflict'});
        if (conflictType != null) {
          add(<String, Object>{'failure.conflict_type': conflictType});
        }
      case CacheFailure():
        add(<String, Object>{'failure.category': 'cache'});
      case PlatformFailure(:final code):
        add(<String, Object>{'failure.category': 'platform'});
        if (code != null) {
          add(<String, Object>{'failure.platform_code': code});
        }
      case CancellationFailure():
        add(<String, Object>{'failure.category': 'cancellation'});
      case StateFailure():
        add(<String, Object>{'failure.category': 'state'});
      case TypeFailure():
        add(<String, Object>{'failure.category': 'type'});
      case UnimplementedFailure():
        add(<String, Object>{'failure.category': 'unimplemented'});
      case UnsupportedFailure():
        add(<String, Object>{'failure.category': 'unsupported'});
      case UnknownFailure():
        add(<String, Object>{'failure.category': 'unknown'});
    }
  }

  @override
  Future<void> dispose() async {
    // BatchSpanProcessor buffers spans ended by reportBatch; flush the
    // global provider so teardown exports them instead of dropping them
    // (review finding on #1678). dartastic's forceFlush is async, so it is
    // awaited here.
    await _flushGlobalProvider();
  }
}

/// The global dartastic tracer provider, or the no-op API provider when the
/// SDK was never initialized.
APITracerProvider _globalTracerProvider() => otelTracerProvider();

/// Flushes the global provider's span processors, when the SDK is live.
///
/// A no-op provider has no processors and no `forceFlush`, so an uninitialized
/// SDK must not make [OtelFailureReporter.dispose] throw during teardown.
Future<void> _flushGlobalProvider() async {
  final provider = _sdkTracerProvider();
  if (provider == null) return;
  await provider.forceFlush();
}

/// The global SDK tracer provider, or `null` when dartastic was never
/// initialized.
TracerProvider? _sdkTracerProvider() {
  try {
    return OTel.tracerProvider();
  } on StateError {
    return null;
  }
}
