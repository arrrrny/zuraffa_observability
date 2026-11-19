import 'dart:async';

import 'package:logging/logging.dart';
import 'package:zuraffa/zuraffa.dart';

import 'otel_failure_reporter.dart';
import 'otel_tracer.dart';

/// Facade for the observability capability.
///
/// The core `Zuraffa.enableOtelReporting(...)` convenience moved here
/// (spec 1653-trim-heavy-deps, issue #1661): call [init] plus
/// [enableOtelReporting] during startup after `Zuraffa.init`.
class ZuraffaObservability {
  ZuraffaObservability._();

  /// The logger uncaught errors are funnelled through.
  ///
  /// A SEVERE record on this logger is picked up by the already-registered
  /// [OtelLogExporter] (which listens on `Logger.root.onRecord` for
  /// `remoteLogLevel` and above) and batched to OTLP `/v1/logs` with
  /// `exception.type` / `exception.message` / `exception.stacktrace`
  /// attributes — no new export path.
  static final Logger _captureLogger = Logger('ZuraffaErrorCapture');

  /// Whether [installGlobalErrorCapture] has armed the zone/isolate capture.
  static bool _installed = false;

  /// The zone armed by [installGlobalErrorCapture], or `null` before it ran.
  static Zone? _captureZone;

  /// Wires the otel-backed [TraceObserver] so core hooks and use cases
  /// surface real trace/span ids.
  static void init() {
    TraceObserver.instance = OtelTracer.instance;
  }

  /// One-call OpenTelemetry failure reporting (the former
  /// `Zuraffa.enableOtelReporting`). When [exportLogs] is true, an
  /// [OtelLogExporter] is built and registered with
  /// `Zuraffa.registerOtelLogExporter` so remote log export survives the
  /// spec-1653 move 1:1 (review finding on #1678).
  static Future<void> enableOtelReporting({
    required Uri collectorEndpoint,
    required String serviceName,
    String? apiKey,
    ReportRetryPolicy? retryPolicy,
    int? maxQueueSize,
    Duration? flushInterval,
    bool persistFailures = false,
    bool exportLogs = false,
    ZuraffaLogLevel remoteLogLevel = ZuraffaLogLevel.warning,
  }) async {
    await Zuraffa.addFailureReporter(
      OtelFailureReporter(
        collectorEndpoint: collectorEndpoint,
        serviceName: serviceName,
        apiKey: apiKey,
      ),
      retryPolicy: retryPolicy,
      maxQueueSize: maxQueueSize,
      flushInterval: flushInterval,
      persistFailures: persistFailures,
    );

    if (exportLogs) {
      Zuraffa.registerOtelLogExporter(
        OtelLogExporter(
          collectorBaseEndpoint: collectorEndpoint,
          serviceName: serviceName,
          apiKey: apiKey,
          remoteLogLevel: remoteLogLevel,
        )..start(),
      );
    }
  }

  /// Pure-Dart half of global error capture.
  ///
  /// Call after [init] + [enableOtelReporting]. It forks the **current** zone
  /// with an uncaught-error handler, so an error that escapes every
  /// `try`/`catch` in the guarded zone (and every zone it forks) still reaches
  /// telemetry:
  ///
  /// - it is logged at `SEVERE` through [Logger] `ZuraffaErrorCapture`, which
  ///   the already-registered [OtelLogExporter] batches to OTLP `/v1/logs`
  ///   with `exception.type` / `exception.message` / `exception.stacktrace`
  ///   attributes; and
  /// - when [reportUncaughtAsSpan] is true (the default), it is *also*
  ///   reported as an [UnknownFailure] through [FailureReporterRegistry] so it
  ///   becomes a `failure.*` span via the registered [OtelFailureReporter].
  ///
  /// The returned [Zone] is the guarded zone: run the app (or its
  /// `runZonedGuarded` bootstrap) inside it so its uncaught errors hit the
  /// handler — `Zone.current.fork(...)` is the pure-Dart equivalent of the
  /// companion `Zuraffa.installUncaughtErrorHandlers` being added to core.
  /// In practice the Flutter half (`FlutterError.onError` /
  /// `PlatformDispatcher.instance.onError`) lives in `zuraffa_flutter`'s
  /// `ZuraffaFlutterErrorCapture.install()`, and the whole app boots through
  /// `Zuraffa.runGuarded(...)` (see the README's "Complete capture wiring"
  /// section).
  ///
  /// Idempotent: a second call returns the zone armed by the first.
  static Future<Zone> installGlobalErrorCapture({
    bool reportUncaughtAsSpan = true,
  }) async {
    if (_installed) return _captureZone!;
    _installed = true;

    final guarded = Zone.current.fork(
      specification: ZoneSpecification(
        handleUncaughtError: (self, parent, zone, error, stackTrace) {
          _captureUncaught(error, stackTrace, reportUncaughtAsSpan);
        },
      ),
    );
    _captureZone = guarded;
    return guarded;
  }

  /// The zone armed by [installGlobalErrorCapture], or `null` before it ran.
  static Zone? get captureZone => _captureZone;

  /// Resets the capture state so [installGlobalErrorCapture] arms a fresh
  /// zone. Test-only: production callers never need this.
  static void resetCaptureForTesting() {
    _installed = false;
    _captureZone = null;
  }

  /// The funnel every uncaught error lands in: log SEVERE (→ OtelLogExporter)
  /// and optionally report a failure span.
  static void _captureUncaught(
    Object error,
    StackTrace stackTrace,
    bool reportUncaughtAsSpan,
  ) {
    _captureLogger.severe('Uncaught error', error, stackTrace);

    if (reportUncaughtAsSpan) {
      FailureReporterRegistry.instance.reportFailure(
        UnknownFailure.from(error, stackTrace),
      );
    }
  }
}
