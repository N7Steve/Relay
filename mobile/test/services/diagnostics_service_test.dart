import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/services/diagnostics_service.dart';

void main() {
  test('starts the application without remote SDK setup', () async {
    var started = false;
    final service = DiagnosticsService();
    await service.initialize(appRunner: () {
      started = true;
    });
    expect(started, isTrue);
    expect(service.navigatorObservers, isEmpty);
  });

  test('preserves callback results and errors', () async {
    final service = DiagnosticsService();
    expect(await service.traceAsync('sync', 'sync', () async => 42), 42);
    await expectLater(
      service.traceAsync(
          'sync', 'sync', () async => throw StateError('failed')),
      throwsStateError,
    );
  });
}
