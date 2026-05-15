import 'dart:async';

import '../models/realtime_timeout.dart';

class RealtimeTimeoutRegistry {
  final Map<RealtimeTimeoutType, Timer> _timers = {};

  bool isActive(RealtimeTimeoutType type) => _timers[type]?.isActive ?? false;

  void start(
    RealtimeTimeoutType type,
    Duration duration,
    void Function() onTimeout,
  ) {
    cancel(type);
    _timers[type] = Timer(duration, () {
      _timers.remove(type);
      onTimeout();
    });
  }

  void cancel(RealtimeTimeoutType type) {
    _timers.remove(type)?.cancel();
  }

  void cancelAll() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }

  void dispose() {
    cancelAll();
  }
}
