import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

enum VoiceDiagnosticLanguage {
  zhTw('zh-TW'),
  taigi('taigi'),
  mixed('mixed-zh-taigi'),
  unknown('unknown');

  const VoiceDiagnosticLanguage(this.value);
  final String value;

  static VoiceDiagnosticLanguage fromValue(String? value) => switch (value) {
        'zh-TW' => zhTw,
        'taigi' => taigi,
        'mixed-zh-taigi' => mixed,
        _ => unknown,
      };
}

enum VoiceDiagnosticEvent {
  captureReady('capture_ready'),
  baselineReady('baseline_ready'),
  baselineWaiting('baseline_waiting'),
  baselineTimeout('baseline_timeout'),
  preferenceChanged('preference_changed'),
  sessionInvalidated('session_invalidated'),
  updateRequested('update_requested'),
  applied('applied'),
  notApplied('not_applied'),
  finalNotCommand('final_not_command'),
  finalStaleRevision('final_stale_revision'),
  finalCommandAccepted('final_command_accepted'),
  preferenceSaveFailed('preference_save_failed'),
  nextInputStarted('next_input_started'),
  responseStarted('response_started'),
  captureHeld('capture_held'),
  ackTimeout('ack_timeout'),
  send('send'),
  sendFailed('send_failed'),
  matched('matched'),
  ignored('ignored'),
  rejected('rejected'),
  unknown('unknown');

  const VoiceDiagnosticEvent(this.code);
  final String code;

  // Only fixed codes cross the recorder boundary; never retain input strings.
  static VoiceDiagnosticEvent fromCode(String code) =>
      values.firstWhere((event) => event.code == code, orElse: () => unknown);
}

enum VoiceDiagnosticFailure { none, timeout, send, rejected, preferenceSave }

/// D1: synchronous, bounded, typed state only. No logging or payload capture.
final class VoiceLanguageDiagnostics {
  VoiceLanguageDiagnostics()
      : enabled = buildEnabled,
        _extensionBridge = _extensions;

  @visibleForTesting
  VoiceLanguageDiagnostics.forTesting({
    bool optIn = true,
    bool release = false,
    VoiceLanguageDiagnosticsExtensions? extensions,
  })  : enabled = !kReleaseMode && !release && optIn,
        _extensionBridge = extensions ?? _extensions;

  static const buildEnabled = !kReleaseMode &&
      bool.fromEnvironment('VOICE_LANGUAGE_DIAGNOSTICS', defaultValue: false);
  static const maxEntries = 128;
  static const maxEntryBytes = 512;
  static const maxSnapshotBytes = 64 * 1024;
  static final _extensions = VoiceLanguageDiagnosticsExtensions();
  static const emptySnapshot = '{"schemaVersion":2,"dropped":0,"events":[]}';

  final bool enabled;
  final VoiceLanguageDiagnosticsExtensions _extensionBridge;
  final _entries = Queue<String>();
  final _clock = Stopwatch()..start();
  int _sequence = 0;
  int _dropped = 0;
  int _bytes = 0;
  bool _collecting = false;
  bool _disposed = false;

  void startCapture() {
    if (!enabled || _disposed) return;
    try {
      _extensionBridge.attach(this);
      clear();
      _collecting = true;
      record(VoiceDiagnosticEvent.captureReady);
    } catch (_) {
      // Diagnostics must never change the voice operation's outcome.
    }
  }

  void record(
    VoiceDiagnosticEvent event, {
    int attempt = 0,
    int generation = 0,
    int revision = 0,
    VoiceDiagnosticLanguage desired = VoiceDiagnosticLanguage.unknown,
    VoiceDiagnosticLanguage applied = VoiceDiagnosticLanguage.unknown,
    bool pending = false,
    bool channelOpen = false,
    bool baselineReady = false,
  }) {
    if (!enabled || !_collecting || _disposed) return;
    try {
      final failure = switch (event) {
        VoiceDiagnosticEvent.ackTimeout ||
        VoiceDiagnosticEvent.baselineTimeout =>
          VoiceDiagnosticFailure.timeout,
        VoiceDiagnosticEvent.sendFailed => VoiceDiagnosticFailure.send,
        VoiceDiagnosticEvent.rejected => VoiceDiagnosticFailure.rejected,
        VoiceDiagnosticEvent.preferenceSaveFailed =>
          VoiceDiagnosticFailure.preferenceSave,
        _ => VoiceDiagnosticFailure.none,
      };
      final entry = jsonEncode({
        'sequence': ++_sequence,
        'elapsedMs': _clock.elapsedMilliseconds,
        'event': event.code,
        'attempt': attempt.clamp(0, 0x7fffffff),
        'generation': generation.clamp(0, 0x7fffffff),
        'revision': revision.clamp(0, 0x7fffffff),
        'desired': desired.value,
        'applied': applied.value,
        'pending': pending,
        'channelOpen': channelOpen,
        'baselineReady': baselineReady,
        'failure': failure.name,
      });
      final size = utf8.encode(entry).length;
      if (size > maxEntryBytes) {
        _dropped++;
        return;
      }
      // Reserve envelope/counter space and one separator per record.
      while (_entries.length >= maxEntries ||
          _bytes + size + 1 > maxSnapshotBytes - 256) {
        _bytes -= _entries.removeFirst().length + 1;
        _dropped++;
      }
      _entries.add(entry);
      _bytes += size + 1;
    } catch (_) {
      // No error message or arbitrary object is retained, even on failure.
    }
  }

  String snapshot() {
    if (!enabled || _disposed) return emptySnapshot;
    return '{"schemaVersion":2,"dropped":$_dropped,"events":[${_entries.join(',')}]}';
  }

  void clear() {
    _entries.clear();
    _bytes = 0;
    _dropped = 0;
  }

  void stopCapture() {
    _collecting = false;
    clear();
  }

  void dispose() {
    stopCapture();
    _disposed = true;
    _clock.stop();
  }
}

/// VM extensions cannot be unregistered. Register once and route to the current
/// owner; disposed owners only return an empty, fixed schema.
class VoiceLanguageDiagnosticsExtensions {
  VoiceLanguageDiagnosticsExtensions()
      : _register = developer.registerExtension;

  @visibleForTesting
  VoiceLanguageDiagnosticsExtensions.forTesting(this._register);

  static const snapshotMethod = 'ext.careCompanion.voiceLanguageSnapshot';
  static const clearMethod = 'ext.careCompanion.voiceLanguageClear';
  final void Function(String, developer.ServiceExtensionHandler) _register;
  final _registered = <String>{};
  VoiceLanguageDiagnostics? _active;

  void attach(VoiceLanguageDiagnostics recorder) {
    if (kReleaseMode || !recorder.enabled || recorder._disposed) return;
    if (!identical(_active, recorder)) _active?.stopCapture();
    _active = recorder;
    for (final method in [snapshotMethod, clearMethod]) {
      if (_registered.contains(method)) continue;
      try {
        _register(method, (_, parameters) async {
          final current = _active;
          if (kReleaseMode ||
              current == null ||
              !current.enabled ||
              current._disposed) {
            return developer.ServiceExtensionResponse.result(
                VoiceLanguageDiagnostics.emptySnapshot);
          }
          // Arguments are deliberately ignored, never evaluated or reflected.
          if (method == clearMethod) current.clear();
          return developer.ServiceExtensionResponse.result(current.snapshot());
        });
        _registered.add(method);
      } catch (_) {
        // A registration failure is not a voice failure; retry next capture.
      }
    }
  }
}
