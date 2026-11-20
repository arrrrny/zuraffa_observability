<!-- ZURAFFA-LAUNCH-PROMO (valid until Dec 1, 2026) -->
## 🦒 [Zuraffa Browser](https://zuraffa.com) — now live

<div align="center">
  <a href="https://zuraffa.com"><img src="https://zuraffa.com/img/zuraffa-browser-home.jpg" alt="Zuraffa Browser — 10 Browsers. One window." width="800"></a>
</div>

**[Zuraffa Browser](https://zuraffa.com)** — the multi-tasking browser for AI agents & humans — is live on the [Mac App Store](https://apps.apple.com/app/id6811352058).

🎁 **Launch offer: 6 months free with code `ZURAFFA`** — no credit card, no subscription, no payment. Redeem in-app until **Dec 1, 2026**.

---

# zuraffa_observability

OpenTelemetry capability for [Zuraffa](https://pub.dev/packages/zuraffa) —
the otel-backed tracer, failure reporter, telemetry hook, and simulation
span capture.

This is an **optional companion package**: it carries the heavyweight
[`dartastic_opentelemetry`](https://pub.dev/packages/dartastic_opentelemetry)
dependency stack so that core-only consumers stay lean
(issue [#1661](https://github.com/arrrrny/zuraffa/issues/1661)). In zuraffa
≤6.x these APIs lived in `package:zuraffa` itself — see the
[core CHANGELOG](https://github.com/arrrrny/zuraffa/blob/master/CHANGELOG.md)
for the full migration map.

Core keeps the light, vendor-free `TraceObserver` seam; call
`ZuraffaObservability.init` to wire the otel-backed observer into it.

## Sealed facade

The OTel value types a consumer needs — the span handle (`APISpan`), the
attribute types (`Attribute` / `Attributes`), the ambient context (`Context`,
`SpanContext`) and the status/span-kind enums — are re-exported from
`package:zuraffa_observability/zuraffa_observability.dart`. **Import this
package, never an OTel package**: reaching past the facade is what made the
`opentelemetry` → `dartastic_opentelemetry` swap (issue
[#4](https://github.com/arrrrny/zuraffa_observability/issues/4)) more
expensive than it needed to be.

## Features

- `ZuraffaObservability` facade — `init()` wires the otel-backed
  `TraceObserver`; `enableOtelReporting(...)` configures export;
  `installGlobalErrorCapture(...)` arms the pure-Dart uncaught-error funnel
- `OtelTracer` — OpenTelemetry tracer wrapper
- `OtelFailureReporter` — reports use-case failures to otel
- `TelemetryHook` — hook-instrumented pipeline spans

## Install

```bash
dart pub add zuraffa_observability
```

Requires `zuraffa: ^7.6.1`.

## Usage

Enable the capability in your Zuraffa project:

```bash
zfa plugin enable observability
```

Then import the surface you need:

```dart
import 'package:zuraffa_observability/zuraffa_observability.dart';
```

## Complete capture wiring for a Flutter app

This package is **pure Dart** (no Flutter dependency in `pubspec.yaml`, by
design) — it owns the **export** side (OTLP traces + logs) and the **pure-Dart
capture** half (zone/isolate uncaught errors). The Flutter widget-binding
handlers live in a sibling package, and the whole app boots through core's
guarded runner. Assemble all four pieces at startup:

1. **Export side** — this package:
   [`ZuraffaObservability.init()`] +
   `ZuraffaObservability.enableOtelReporting(...)` wire the otel-backed
   `TraceObserver`, the `OtelFailureReporter`, and (with `exportLogs: true`)
   the `OtelLogExporter` that ships `WARNING`+ records to OTLP `/v1/logs`.
2. **Pure-Dart capture** — this package:
   [`ZuraffaObservability.installGlobalErrorCapture()`] forks the current zone
   with an uncaught-error handler, so an error that escapes every
   `try`/`catch` is logged at `SEVERE` (→ `OtelLogExporter`) and, with
   `reportUncaughtAsSpan: true`, reported as a `failure.*` span via
   `FailureReporterRegistry`. Run the app inside the returned zone (or boot
   through step 4, which does this for you).
3. **Flutter capture** — [`arrrrny/zuraffa_flutter`](https://github.com/arrrrny/zuraffa_flutter):
   `ZuraffaFlutterErrorCapture.install()` wires `FlutterError.onError` and
   `PlatformDispatcher.instance.onError` into the same funnel (these cannot
   live here — no Flutter dependency).
4. **Guarded boot** — [`arrrrny/zuraffa`](https://github.com/arrrrny/zuraffa):
   boot the app through `Zuraffa.runGuarded(...)` so the root zone is guarded
   and every uncaught error reaches the capture path armed in step 2.

```dart
import 'package:zuraffa/zuraffa.dart';
import 'package:zuraffa_observability/zuraffa_observability.dart';
// import 'package:zuraffa_flutter/zuraffa_flutter.dart'; // step 3

Future<void> main() async {
  ZuraffaObservability.init();                       // 1
  await ZuraffaObservability.enableOtelReporting(     // 1
    collectorEndpoint: Uri.parse('https://otel.example.com/v1/traces'),
    serviceName: 'my_app',
    exportLogs: true,
  );
  await ZuraffaObservability.installGlobalErrorCapture(); // 2
  // ZuraffaFlutterErrorCapture.install();            // 3

  // 4 — boot the app inside the guarded zone.
  await Zuraffa.runGuarded(() async {
    runApp(const MyApp());
  });
}
```

Because the capture funnels uncaught errors through `Logger`, they flow to
SigNoz logs automatically through the already-registered `OtelLogExporter` —
no new export path.

## Development

This repository is a standalone split from the core `zuraffa` monorepo
(issue [#1690](https://github.com/arrrrny/zuraffa/issues/1690) §4) with full
git history preserved. Its `pubspec.yaml` declares a hosted
`zuraffa: ^7.6.1` constraint plus a `dependency_overrides` entry resolving
`zuraffa` to the local core checkout — so a sibling checkout of
[arrrrny/zuraffa](https://github.com/arrrrny/zuraffa) at `../zuraffa` is
required for `dart pub get`, `dart analyze`, and `dart test`:

```text
~/Developer/
├── zuraffa/                # core checkout (any branch)
└── zuraffa_observability/  # this repository
```

CI provides that sibling checkout automatically. See
[PUBLISH.md](PUBLISH.md) before releasing.

## Links

- [Repository](https://github.com/arrrrny/zuraffa_observability)
- [Issue tracker](https://github.com/arrrrny/zuraffa_observability/issues)
- [Zuraffa core](https://github.com/arrrrny/zuraffa) ·
  [zuraffa on pub.dev](https://pub.dev/packages/zuraffa)
