# zuraffa_observability

OpenTelemetry capability for [Zuraffa](https://pub.dev/packages/zuraffa) —
the otel-backed tracer, failure reporter, telemetry hook, and simulation
span capture.

This is an **optional companion package**: it carries the heavyweight
`opentelemetry` dependency stack so that core-only consumers stay lean
(issue [#1661](https://github.com/arrrrny/zuraffa/issues/1661)). In zuraffa
≤6.x these APIs lived in `package:zuraffa` itself — see the
[core CHANGELOG](https://github.com/arrrrny/zuraffa/blob/master/CHANGELOG.md)
for the full migration map.

Core keeps the light, vendor-free `TraceObserver` seam; call
`ZuraffaObservability.init` to wire the otel-backed observer into it.

## Features

- `ZuraffaObservability` facade — `init()` wires the otel-backed
  `TraceObserver`; `enableOtelReporting(...)` configures export
- `OtelTracer` — OpenTelemetry tracer wrapper
- `OtelFailureReporter` — reports use-case failures to otel
- `TelemetryHook` — hook-instrumented pipeline spans

## Install

```bash
dart pub add zuraffa_observability
```

Requires `zuraffa: ^7.0.0`.

## Usage

Enable the capability in your Zuraffa project:

```bash
zfa plugin enable observability
```

Then import the surface you need:

```dart
import 'package:zuraffa_observability/zuraffa_observability.dart';
```

## Development

This repository is a standalone split from the core `zuraffa` monorepo
(issue [#1690](https://github.com/arrrrny/zuraffa/issues/1690) §4) with full
git history preserved. Its `pubspec.yaml` declares a hosted
`zuraffa: ^7.0.0` constraint plus a `dependency_overrides` entry resolving
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
