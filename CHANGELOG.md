## 8.0.0 - 2026-11-19

- **8.0.0 (breaking)** — the OTel base moved from the deprecated
  `opentelemetry` package (Workiva re-export shim, `^0.18.11`) to
  `dartastic_opentelemetry` 1.1.0-beta.17, the CNCF donation candidate whose
  people now are the OpenTelemetry Dart & Flutter SIG (issue
  [#4](https://github.com/arrrrny/zuraffa_observability/issues/4)). The tracer
  pipeline, the OTLP/HTTP export path, the simulation capture-and-assert
  adapter and the failure-reporter boot wiring were ported; span names,
  attribute keys and the `enableOtelReporting(...)` signature are unchanged.
  - `OtelTracer.startSpan` returns dartastic's `APISpan` and takes
    `Attributes` instead of `List<Attribute>`; `startSpan` does **not**
    activate — activation is `OtelTracer.trace` / `traceSync` (dartastic's
    `withSpan`, zone-scoped) or `Context.current.withSpan(span).run(...)`.
  - `StatusCode` is now `SpanStatusCode` (`Unset` / `Ok` / `Error`), and the
    ambient span is read with `OtelTracer.spanFromContext([Context])` /
    `OtelTracer.instance.currentSpanContext` — the sealed replacement for the
    OTel packages' `spanFromContext(Context())`.
  - **Sealed facade**: the span/attribute/context value types are re-exported
    from `lib/zuraffa_observability.dart`, so downstream apps never import an
    OTel package directly.
  - `OtelFailureReporter` boots dartastic via `OTel.initialize` with
    `BatchSpanProcessor` + `OtlpHttpSpanExporter` (the collector endpoint and
    the `Authorization: Bearer` header carry over unchanged) and keeps the
    dispose-time `forceFlush` (review finding on #1678); metrics/logs export
    stay off, so the `Logger.root` → `OtelLogExporter` pipeline is untouched.
  - New `test/zone_context_parity_test.dart`: an ambient span read inside
    nested async execution, no bleed between two concurrent traces, and the
    `traceSync` path.
  - `OtelAdapter` implements dartastic's `SpanExporter` and captures the same
    `SpanSnapshot` shape (name, status, attributes) the simulation
    certification asserts on.
- `ZuraffaObservability.installGlobalErrorCapture()` — the pure-Dart half of
  global error capture (issue #1): forks the current zone with an
  uncaught-error handler so an error that escapes every `try`/`catch` is
  logged at `SEVERE` (→ `OtelLogExporter`, batched to OTLP `/v1/logs`) and,
  with `reportUncaughtAsSpan: true`, reported as a `failure.*` span via
  `FailureReporterRegistry`. README documents the full Flutter capture wiring
  across `zuraffa` / `zuraffa_flutter` / `zuraffa_observability`.

## 7.5.1 - 2026-11-19

- `ZuraffaObservability.installGlobalErrorCapture()` — the pure-Dart half of
  global error capture (issue #1): forks the current zone with an
  uncaught-error handler so an error that escapes every `try`/`catch` is
  logged at `SEVERE` (→ `OtelLogExporter`, batched to OTLP `/v1/logs`) and,
  with `reportUncaughtAsSpan: true`, reported as a `failure.*` span via
  `FailureReporterRegistry`. README documents the full Flutter capture wiring
  across `zuraffa` / `zuraffa_flutter` / `zuraffa_observability`.

Purely additive patch release: a consumer resolving `^7.5.0` can now reach the
capture API without a master pin (zuraffa#2106).

## 7.5.0 - 2026-11-15

Release 7.5.0: Signal-backed view-state migration template with SignalScope ownership (#2076); signal listener/subscription cleanup on eager-delivery throw (#2081, #2083); UseCase/StreamUseCase catch-all SEVERE logs now carry the cause (#2077, #2079); dependencies upgraded and pinned to latest resolvable.

## 7.4.2 - 2026-11-13

- Mono-version fleet alignment to 7.4.2; internal dependencies refreshed; xml override 7.1.0.

## 7.4.1 - 2026-11-11

Fleet release 7.4.1: core adds zfa tunnel (Cloudflare-hosted MCP servers), MCP streamable-HTTP transport with usecase tools, blocking lifecycle hooks (#2032), typed tool param coercion (#2061); whole fleet mono-aligned to 7.4.1.

## 7.3.6 - 2026-11-02

- Mono-version fleet alignment to 7.3.6; internal dependencies refreshed; xml override 7.1.0.

## 7.3.2 - 2026-10-31

Mono-version fleet alignment to 7.3.2: outbound send port lands in zuraffa_intents (shareText/shareFiles behind ShareIntentService); the whole family ships at one version.

## 7.3.0 - 2026-10-28

- Mono-version fleet alignment: the whole zuraffa family ships at 7.3.0 together with the core.
- `zuraffa` dependency constraints unified to ^7.3.0; cross-family constraints move with the release.
- Fleet-wide `dependency_overrides: xml: 7.1.0`; README install guides refreshed to 7.3.0.

## 7.2.0 - 2026-10-28

- Mono-version fleet alignment: the whole zuraffa family now ships at the same version as the core.
- `zuraffa` dependency constraint unified to ^7.2.0 across the fleet.
- zuraffa_storage now wraps the maintained `zuraffa_minio` fork instead of the abandoned `minio` package (xml 7 compatible).
- Fleet-wide `dependency_overrides: xml: 7.1.0` policy; README install guides refreshed to the release version.

# Changelog

## 0.1.1

- Drop the local-sibling `dependency_overrides` entry: the hosted
  `zuraffa: ^7.0.0` constraint resolves on its own now that zuraffa 7.x is
  published, so development no longer needs the path pin.
- `test` bumped to `^1.33.0`.

## 0.1.0

- Initial standalone release: split from the zuraffa monorepo
  (`packages/zuraffa_observability`) into its own repository with full
  git history preserved (issue #1690 §4).
- Publish shape for independent releases: hosted `zuraffa: ^7.0.0`
  constraint with a local-sibling `dependency_overrides` entry for
  development.
