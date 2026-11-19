/// OpenTelemetry capability for Zuraffa (optional companion package).
///
/// Spec 1653-trim-heavy-deps (issue #1661): the otel-backed tracer,
/// failure reporter, telemetry hook, and simulation span capture moved
/// out of the core package. Core keeps the light `TraceObserver` seam —
/// call `ZuraffaObservability.init` to wire the otel-backed observer.
///
/// ## Sealed facade (issue #4)
///
/// The OTel value types a consumer needs — the span handle ([APISpan]), the
/// attribute types ([Attribute] / [Attributes]), the ambient context
/// ([Context] and [SpanContext]) and the status/span-kind enums — are
/// re-exported here, so a downstream app never imports an OTel package
/// directly. That leak is what made the `opentelemetry` → `dartastic` swap
/// expensive: consumers reached past this package for `Attributes` and
/// `Context` and had to migrate in lockstep with no compile-time nudge from
/// the package that owned the choice.
library;

export 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart'
    show
        APISpan,
        APITracer,
        APITracerProvider,
        Attribute,
        Attributes,
        Context,
        ContextKey,
        OTel,
        SpanContext,
        SpanEvent,
        SpanId,
        SpanKind,
        SpanLink,
        SpanStatusCode,
        TraceFlags,
        TraceId,
        TraceState;

export 'src/facade.dart';
export 'src/otel_adapter.dart';
export 'src/otel_failure_reporter.dart';
export 'src/otel_tracer.dart';
export 'src/span_capture.dart';
export 'src/telemetry_hook.dart';
