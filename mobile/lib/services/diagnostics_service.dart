import 'dart:async';
import 'package:flutter/widgets.dart';
import 'log_service.dart';

/// Local diagnostics only. No SDK, network transport or user identity storage.
class DiagnosticsService {
  static final DiagnosticsService instance = DiagnosticsService();

  List<NavigatorObserver> get navigatorObservers => const [];

  Future<void> initialize(
      {required FutureOr<void> Function() appRunner}) async {
    await appRunner();
  }

  void addBreadcrumb(String category, String message,
      {Map<String, dynamic>? data}) {
    LogService.instance.debug(category, LogService.sanitize(message));
  }

  Future<T> traceAsync<T>(
      String operation, String description, Future<T> Function() callback,
      {Map<String, dynamic>? data, bool Function(T result)? isSuccess}) async {
    return await callback();
  }

  Object? startSpan(String operation, String description,
          {Map<String, dynamic>? data}) =>
      Stopwatch()..start();

  Future<void> finishSpan(Object? span,
      {required bool success, Object? throwable}) async {
    if (span is Stopwatch) {
      span.stop();
      LogService.instance.debug('Diagnostics',
          'Operation completed: success=$success duration_ms=${span.elapsedMilliseconds}');
    }
  }

  Future<void> captureHandledException(Object exception, StackTrace? stackTrace,
      {required String operation}) async {
    LogService.instance.error('Diagnostics',
        '${LogService.sanitize(operation)}: ${exception.runtimeType}');
  }
}
