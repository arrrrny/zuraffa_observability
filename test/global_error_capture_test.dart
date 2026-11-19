// Issue #1 — the pure-Dart capture half of global error capture.
//
// The package ships the export side (`OtelLogExporter` for WARNING+ records,
// `OtelFailureReporter` for failure spans) but captures nothing: an uncaught
// error in a family app never becomes a record or a span, because nobody arms
// `runZonedGuarded` / isolate error ports.
//
// Acceptance criteria (issue #1):
//   1. After `init` + `enableOtelReporting` + `installGlobalErrorCapture` in a
//      pure-Dart test, an uncaught isolate/zone error produces
//      (a) a batched OTLP log record with exception attributes against a fake
//          collector, and
//      (b) when the span flag is on, a reported failure entry.
//   2. The package stays pure Dart (no Flutter dependency).
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:zuraffa/zuraffa.dart';
import 'package:zuraffa_observability/zuraffa_observability.dart';

/// Captures every `POST` body a fake collector receives and answers `202`.
class _CapturingClient extends http.BaseClient {
  final List<Map<String, dynamic>> payloads = <Map<String, dynamic>>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().bytesToString();
    if (body.isNotEmpty) {
      payloads.add(jsonDecode(body) as Map<String, dynamic>);
    }
    return http.StreamedResponse(
      Stream.value(
        utf8.encode(
          jsonEncode({'partialSuccess': {}, 'rejectedLogRecords': 0}),
        ),
      ),
      202,
      request: request,
    );
  }
}

/// Walks every captured OTLP `resourceLogs` payload and returns the flat list
/// of log records.
List<Map<String, dynamic>> _logRecords(_CapturingClient client) {
  final records = <Map<String, dynamic>>[];
  for (final payload in client.payloads) {
    for (final rl in (payload['resourceLogs'] as List)) {
      for (final sl in (rl['scopeLogs'] as List)) {
        for (final rec in (sl['logRecords'] as List)) {
          records.add(rec as Map<String, dynamic>);
        }
      }
    }
  }
  return records;
}

/// Returns the `value.stringValue` of [key] from a record's attributes, or null.
String? _attr(Map<String, dynamic> record, String key) {
  for (final a in (record['attributes'] as List)) {
    if (a['key'] == key) {
      return (a['value'] as Map<String, dynamic>)['stringValue'] as String?;
    }
  }
  return null;
}

/// A [FailureReporter] that records every [FailureReport] it is handed.
///
/// The capture span path runs `FailureReporterRegistry → OtelFailureReporter →
/// OTLP /v1/traces`, so a span assertion would have to decode the protobuf
/// trace payload. This capturing reporter observes the same reports one step
/// earlier — at the registry boundary, which is exactly what
/// `reportUncaughtAsSpan` controls — so the test fails if that branch is
/// removed or broken, without coupling to the trace wire format.
class _CapturingFailureReporter extends FailureReporter {
  final List<FailureReport> reports = <FailureReport>[];

  @override
  String get id => 'test-capturing-failure-reporter';

  @override
  Future<void> reportBatch(List<FailureReport> batch) async {
    reports.addAll(batch);
  }
}

void main() {
  group('ZuraffaObservability.installGlobalErrorCapture', () {
    late _CapturingClient client;
    late _CapturingFailureReporter failureReporter;

    setUp(() async {
      client = _CapturingClient();
      failureReporter = _CapturingFailureReporter();

      // Reset the failure registry and the capture state so each test starts
      // clean and arms a fresh zone.
      await FailureReporterRegistry.instance.reset();
      ZuraffaObservability.resetCaptureForTesting();

      // Wire the export side. enableOtelReporting builds an OtelLogExporter
      // with its own http.Client, so we register an exporter pointed at the
      // same collector shape but wired to our fake transport — the capture
      // path under test is identical either way. A short flush interval keeps
      // the test fast (the production default is 5s).
      ZuraffaObservability.init();
      await Zuraffa.addFailureReporter(failureReporter);
      await Zuraffa.addFailureReporter(
        OtelFailureReporter(
          collectorEndpoint: Uri.parse('http://fake/v1/traces'),
          serviceName: 'global-capture-test',
        ),
      );
      Zuraffa.registerOtelLogExporter(
        OtelLogExporter(
          collectorBaseEndpoint: Uri.parse('http://fake/v1/traces'),
          serviceName: 'global-capture-test',
          remoteLogLevel: ZuraffaLogLevel.warning,
          flushInterval: const Duration(milliseconds: 20),
          httpClient: client,
        )..start(),
      );
    });

    tearDown(() async {
      await Zuraffa.disposeFailureReporters();
      await FailureReporterRegistry.instance.reset();
      ZuraffaObservability.resetCaptureForTesting();
    });

    test('an uncaught zone error produces a batched OTLP log record with '
        'exception attributes', () async {
      final error = StateError('boom-from-zone');
      // Run the throwing code inside the zone armed by
      // installGlobalErrorCapture, so the uncaught error hits the handler.
      final zone = await ZuraffaObservability.installGlobalErrorCapture();
      zone.run(() {
        scheduleMicrotask(() => throw error);
      });

      // Let the microtask + the exporter's batching run.
      await Future<void>.delayed(const Duration(milliseconds: 120));

      final records = _logRecords(client);
      final capturedSevere = records.where(
        (r) => r['severityText'] == 'SEVERE',
      );
      expect(
        capturedSevere,
        isNotEmpty,
        reason: 'uncaught error must produce a SEVERE OTLP log record',
      );
      final rec = capturedSevere.first;
      expect(_attr(rec, 'exception.type'), contains('StateError'));
      expect(_attr(rec, 'exception.message'), contains('boom-from-zone'));
      expect(_attr(rec, 'exception.stacktrace'), isNotNull);
    });

    test(
      'a reported failure entry is produced when the span flag is on',
      () async {
        // reportUncaughtAsSpan defaults to true: the uncaught error is routed
        // through FailureReporterRegistry as an UnknownFailure, which the
        // registered OtelFailureReporter turns into a `failure.*` span. We
        // assert that a failure report actually reached a registered reporter —
        // the registry is the single gate this flag controls — instead of
        // re-reading the SEVERE log path that test 1 already covers.
        final error = ArgumentError('boom-as-failure');
        final zone = await ZuraffaObservability.installGlobalErrorCapture();
        zone.run(() {
          scheduleMicrotask(() => throw error);
        });

        // Let the microtask fire and the capture path enqueue the failure.
        await Future<void>.delayed(const Duration(milliseconds: 120));

        // Flush the failure queue so the captured reporter receives the report.
        await Zuraffa.flushFailureReports();

        final reported = failureReporter.reports.where(
          (r) => r.failure is UnknownFailure,
        );
        expect(
          reported,
          isNotEmpty,
          reason:
              'the uncaught error must be reported through the failure '
              'reporter path (→ failure.* span) when reportUncaughtAsSpan is '
              'on',
        );
        final report = reported.first;
        expect(report.failure.message, contains('boom-as-failure'));
        expect(
          report.failure.stackTrace ?? report.stackTrace,
          isNotNull,
          reason: 'the report must carry the originating stack trace',
        );
      },
    );

    test(
      'no failure entry is produced when the span flag is off',
      () async {
        // reportUncaughtAsSpan: false must skip the failure-reporter branch
        // entirely — the uncaught error is still logged (test 1's SEVERE path),
        // but nothing reaches the failure reporter queue.
        final error = ArgumentError('boom-no-span');
        final zone = await ZuraffaObservability.installGlobalErrorCapture(
          reportUncaughtAsSpan: false,
        );
        zone.run(() {
          scheduleMicrotask(() => throw error);
        });

        await Future<void>.delayed(const Duration(milliseconds: 120));
        await Zuraffa.flushFailureReports();

        expect(
          failureReporter.reports,
          isEmpty,
          reason:
              'with reportUncaughtAsSpan off, no failure report may reach the '
              'reporters',
        );
      },
    );
  });
}
