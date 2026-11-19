import 'dart:async';

import 'package:logging/logging.dart';
import 'package:zuraffa/zuraffa.dart' show TraceObserver;
import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart'
    show
        APISpan,
        APITracer,
        APITracerProvider,
        Attribute,
        Attributes,
        Context,
        OTel,
        OTelAPI,
        SpanContext,
        SpanKind,
        SpanStatusCode;

// ---------------------------------------------------------------------------
// OtelTracer
// ---------------------------------------------------------------------------

/// Thin singleton for creating and managing application-level OTel traces.
///
/// Works alongside [OtelFailureReporter] — both share the same global
/// dartastic [TracerProvider] registered at startup via
/// [OtelFailureReporter.initialize].
///
/// ## Purpose
///
/// [OtelFailureReporter] handles the *error path* — it automatically wraps
/// each [AppFailure] in a span. [OtelTracer] handles the *happy path and
/// business operations* — you decide which operations are worth tracing
/// and what attributes to attach.
///
/// ## Usage
///
/// ```dart
/// // Wrap a business operation in a span (recommended — handles end/error automatically)
/// final order = await OtelTracer.instance.trace(
///   'checkout.process',
///   attributes: Attributes.of({'order.id': orderId}),
///   () async {
///     return await processOrder(orderId);
///   },
/// );
///
/// // Manual span control
/// final span = OtelTracer.instance.startSpan(
///   'inventory.reserve',
///   attributes: Attributes.of({'product.id': productId}),
/// );
/// try {
///   await reserveInventory(productId);
///   span.end();
/// } catch (e, st) {
///   OtelTracer.instance.endSpanWithError(span, e, st);
/// }
/// ```
///
/// ## Trace Context in Artifacts
///
/// When [ArtifactPublisher] publishes an artifact, it calls
/// [OtelTracer.currentTraceId] and [OtelTracer.currentSpanId] to stamp
/// the active span context onto the artifact. This lets you navigate from
/// any artifact in storage directly to the trace in Jaeger/Grafana.
///
/// ## Initialization
///
/// [OtelTracer] becomes active automatically when [OtelFailureReporter]
/// registers the global dartastic tracer provider during
/// `ZuraffaObservability.enableOtelReporting`. No separate setup is required.
/// Before that, every call is inert (dartastic's no-op API tracer), exactly as
/// the pre-dartastic shim behaved.
class OtelTracer implements TraceObserver {
  OtelTracer._();

  static final OtelTracer _instance = OtelTracer._();

  /// The singleton instance.
  static OtelTracer get instance => _instance;

  static final Logger _logger = Logger('OtelTracer');

  /// The instrumentation name used when getting the [APITracer].
  ///
  /// Defaults to `'zuraffa-tracer'`. Override before first use if you want
  /// a custom scope name to appear in your telemetry backend.
  String instrumentationName = 'zuraffa-tracer';

  // ---------------------------------------------------------------------------
  // Active span context
  // ---------------------------------------------------------------------------

  /// The W3C trace ID of the currently active span, or `null` if no span
  /// is active or the active span context is invalid.
  ///
  /// Format: 32 lowercase hex characters (128-bit), e.g.
  /// `'4bf92f3577b34da6a3ce929d0e0e4736'`
  ///
  /// Used by [ArtifactPublisher] to stamp artifacts with the active trace ID
  /// so you can cross-reference from storage back to the trace.
  String? get currentTraceId {
    try {
      final id = currentSpanContext?.traceId.toString();
      // Guard against the all-zeros invalid trace id
      return (id == null || RegExp(r'^0+$').hasMatch(id)) ? null : id;
    } catch (_) {
      return null;
    }
  }

  /// The W3C span ID of the currently active span, or `null` if no span
  /// is active or the active span context is invalid.
  ///
  /// Format: 16 lowercase hex characters (64-bit), e.g.
  /// `'00f067aa0ba902b7'`
  String? get currentSpanId {
    try {
      final id = currentSpanContext?.spanId.toString();
      return (id == null || RegExp(r'^0+$').hasMatch(id)) ? null : id;
    } catch (_) {
      return null;
    }
  }

  /// The [SpanContext] of the span active in the current zone, or `null` when
  /// no valid span is active.
  ///
  /// dartastic keeps the active span in a `Zone` value, so this reads back the
  /// span an enclosing `OtelTracer.trace` / `traceSync` activated — including
  /// from nested async code that never received the span.
  SpanContext? get currentSpanContext {
    try {
      final spanContext = Context.current.spanContext;
      return (spanContext == null || !spanContext.isValid) ? null : spanContext;
    } catch (_) {
      return null;
    }
  }

  /// The span active in the current zone, or `null` when none is active.
  APISpan? get currentSpan => Context.current.span;

  /// The span active in [context] (defaulting to the ambient one).
  ///
  /// The sealed replacement for the OTel packages' `spanFromContext(Context())`
  /// — a consumer that used to import `package:opentelemetry/api.dart` for that
  /// one call now imports nothing but this package.
  static APISpan? spanFromContext([Context? context]) =>
      (context ?? Context.current).span;

  // ---------------------------------------------------------------------------
  // Span lifecycle
  // ---------------------------------------------------------------------------

  /// The dartastic tracer every span is created from.
  ///
  /// Falls back to dartastic's no-op API tracer while the SDK is not
  /// initialized, so the hook and the tracer stay inert instead of throwing.
  APITracer get tracer => _getTracer();

  /// Start a new span as a child of the currently active context.
  ///
  /// The span is NOT activated — dartastic's `startSpan` never activates. Use
  /// [trace] / [traceSync] to have the span ambient inside the wrapped
  /// computation, or `Context.current.withSpan(span).run(...)` yourself.
  ///
  /// You are responsible for calling [endSpan] or [endSpanWithError] when done.
  /// Prefer [trace] when possible — it handles lifecycle automatically.
  ///
  /// ```dart
  /// final span = OtelTracer.instance.startSpan(
  ///   'payment.authorise',
  ///   attributes: Attributes.of({'payment.provider': 'stripe'}),
  /// );
  /// ```
  APISpan startSpan(
    String name, {
    Attributes? attributes,
    SpanKind kind = SpanKind.internal,
    Context? parentContext,
  }) {
    try {
      return _getTracer().startSpan(
        name,
        context: parentContext ?? Context.current,
        kind: kind,
        attributes: attributes,
      );
    } catch (e) {
      _logger.warning('OtelTracer.startSpan failed for "$name": $e');
      rethrow;
    }
  }

  /// End a span successfully.
  void endSpan(APISpan span) {
    try {
      span.end();
    } catch (e) {
      _logger.warning('OtelTracer.endSpan failed: $e');
    }
  }

  /// End a span in an error state, recording the exception.
  void endSpanWithError(APISpan span, Object error, [StackTrace? stackTrace]) {
    try {
      span.setStatus(SpanStatusCode.Error, error.toString());
      span.recordException(error, stackTrace: stackTrace ?? StackTrace.current);
      span.end();
    } catch (e) {
      _logger.warning('OtelTracer.endSpanWithError failed: $e');
    }
  }

  /// Attach a span to the current context and run [fn] within it.
  ///
  /// The span is active for the duration of [fn], meaning [currentTraceId]
  /// and [currentSpanId] will return its IDs while inside [fn] — including in
  /// nested async execution, because activation is zone-scoped. The span is
  /// ended automatically — with error status if [fn] throws.
  ///
  /// ```dart
  /// final result = await OtelTracer.instance.trace(
  ///   'cart.checkout',
  ///   attributes: Attributes.of({'cart.id': cartId}),
  ///   () async => await checkoutService.process(cartId),
  /// );
  /// ```
  Future<T> trace<T>(
    String name,
    Future<T> Function() fn, {
    Attributes? attributes,
    SpanKind kind = SpanKind.internal,
  }) {
    // Capture the parent context *before* forking so that the new span is
    // correctly linked as a child of whatever span was active at the call-site.
    final parentContext = Context.current;
    final span = startSpan(
      name,
      attributes: attributes,
      kind: kind,
      parentContext: parentContext,
    );

    return parentContext.withSpan(span).run(() async {
      try {
        final result = await fn();
        endSpan(span);
        return result;
      } catch (e, st) {
        endSpanWithError(span, e, st);
        rethrow;
      }
    });
  }

  /// Synchronous variant of [trace] for non-async operations.
  T traceSync<T>(
    String name,
    T Function() fn, {
    Attributes? attributes,
    SpanKind kind = SpanKind.internal,
  }) {
    final parentContext = Context.current;
    final span = startSpan(
      name,
      attributes: attributes,
      kind: kind,
      parentContext: parentContext,
    );

    return parentContext.withSpan(span).runSync(() {
      try {
        final result = fn();
        endSpan(span);
        return result;
      } catch (e, st) {
        endSpanWithError(span, e, st);
        rethrow;
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Span enrichment
  // ---------------------------------------------------------------------------

  /// Add an event to [span] — a timestamped annotation within the span.
  ///
  /// Use events for notable moments during a span's lifetime, e.g.:
  /// ```dart
  /// OtelTracer.instance.addEvent(
  ///   span,
  ///   'cache.miss',
  ///   attributes: Attributes.of({'cache.key': key}),
  /// );
  /// ```
  void addEvent(APISpan span, String name, {Attributes? attributes}) {
    try {
      span.addEventNow(name, attributes);
    } catch (e) {
      _logger.warning('OtelTracer.addEvent failed: $e');
    }
  }

  /// Set (or replace) one attribute on [span].
  void setAttribute(APISpan span, Attribute<Object> attribute) {
    try {
      span.addAttributes(Attributes.of({attribute.key: attribute.value}));
    } catch (e) {
      _logger.warning('OtelTracer.setAttribute failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  APITracer _getTracer() {
    try {
      return OTel.tracerProvider().getTracer(instrumentationName);
    } on StateError {
      // The SDK is not initialized (no OtelFailureReporter ran yet): the
      // no-op API tracer keeps every call inert instead of throwing.
      return OTelAPI.tracerProvider().getTracer(instrumentationName);
    }
  }
}

/// The tracer provider every span flows through — dartastic's global SDK
/// provider once [OtelFailureReporter.initialize] registered it, and the
/// no-op API provider before that.
///
/// Exposed so a companion (the failure reporter's dispose-time flush) can reach
/// the same provider without importing dartastic itself.
APITracerProvider otelTracerProvider() {
  try {
    return OTel.tracerProvider();
  } on StateError {
    return OTelAPI.tracerProvider();
  }
}
