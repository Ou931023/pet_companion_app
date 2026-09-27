import 'dart:convert';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/services/voice_language_diagnostics.dart';

void main() {
  final handlers = <String, ServiceExtensionHandler>{};
  late VoiceLanguageDiagnosticsExtensions bridge;
  late VoiceLanguageDiagnostics recorder;

  setUp(() {
    handlers.clear();
    bridge = VoiceLanguageDiagnosticsExtensions.forTesting((name, handler) {
      expect(handlers.containsKey(name), isFalse);
      handlers[name] = handler;
    });
    recorder = VoiceLanguageDiagnostics.forTesting(extensions: bridge);
  });
  tearDown(() => recorder.dispose());

  Future<Map<String, dynamic>> invoke(String method,
      [Map<String, String> params = const {}]) async {
    final response = await handlers[method]!(method, params);
    return jsonDecode(response.result!) as Map<String, dynamic>;
  }

  test('production gate is opt-in AND nonrelease', () {
    final production = VoiceLanguageDiagnostics();
    expect(
        production.enabled,
        !kReleaseMode &&
            const bool.fromEnvironment('VOICE_LANGUAGE_DIAGNOSTICS',
                defaultValue: false));
    production.startCapture();
    production.record(VoiceDiagnosticEvent.applied);
    expect((jsonDecode(production.snapshot())['events'] as List).length,
        production.enabled ? 2 : 0);
    production.dispose();
    for (final (optIn, release) in [
      (false, false),
      (false, true),
      (true, true)
    ]) {
      final disabled = VoiceLanguageDiagnostics.forTesting(
          optIn: optIn, release: release, extensions: bridge);
      disabled.startCapture();
      disabled.record(VoiceDiagnosticEvent.applied);
      expect(disabled.snapshot(), VoiceLanguageDiagnostics.emptySnapshot);
      expect(handlers, isEmpty);
      disabled.dispose();
    }
  });

  test('bounded FIFO, exact bytes, overflow, monotonic sequence and clear', () {
    recorder.startCapture();
    for (var i = 0; i < 1000; i++) {
      recorder.record(VoiceDiagnosticEvent.preferenceSaveFailed,
          attempt: 0x7fffffffffffffff,
          generation: 0x7fffffffffffffff,
          revision: 0x7fffffffffffffff,
          desired: VoiceDiagnosticLanguage.mixed,
          applied: VoiceDiagnosticLanguage.mixed,
          pending: true,
          channelOpen: true);
    }
    final encoded = recorder.snapshot();
    final data = jsonDecode(encoded) as Map;
    final events = data['events'] as List;
    expect(events, hasLength(128));
    expect(data['dropped'], 873);
    expect(events.first['sequence'], 874);
    expect(events.last['sequence'], 1001);
    expect(utf8.encode(encoded).length, lessThanOrEqualTo(64 * 1024));
    for (final event in events) {
      expect(utf8.encode(jsonEncode(event)).length, lessThanOrEqualTo(512));
      expect(event['attempt'], 0x7fffffff);
      expect(event['elapsedMs'], greaterThanOrEqualTo(0));
    }
    recorder.clear();
    expect(recorder.snapshot(), VoiceLanguageDiagnostics.emptySnapshot);
    recorder.record(VoiceDiagnosticEvent.applied);
    expect(
        (jsonDecode(recorder.snapshot())['events'] as List).single['sequence'],
        1002);
  });

  test('all enum combinations remain within entry and snapshot bounds', () {
    recorder.startCapture();
    for (final event in VoiceDiagnosticEvent.values) {
      for (final desired in VoiceDiagnosticLanguage.values) {
        for (final applied in VoiceDiagnosticLanguage.values) {
          recorder.record(event, desired: desired, applied: applied);
          final raw = recorder.snapshot();
          expect(utf8.encode(raw).length, lessThanOrEqualTo(64 * 1024));
          final last = (jsonDecode(raw)['events'] as List).last;
          expect(utf8.encode(jsonEncode(last)).length, lessThanOrEqualTo(512));
        }
      }
    }
  });

  test('fixed schema rejects arbitrary values and never reflects parameters',
      () async {
    recorder.startCapture();
    const forbidden = [
      'TRANSCRIPT_SENTINEL',
      'PROMPT_SENTINEL',
      'NAME_SENTINEL',
      'MEMORY_SENTINEL',
      'SESSION_ID_SENTINEL',
      'EVENT_ID_SENTINEL',
      'ITEM_ID_SENTINEL',
      'ACCOUNT_SENTINEL',
      'DEVICE_SENTINEL',
      'AUDIO_SENTINEL',
      'SDP_SENTINEL',
      'https://URL_SENTINEL',
      'CREDENTIAL_SENTINEL',
      'KEY_SENTINEL',
      'ERROR_SENTINEL',
      'HASH_SENTINEL',
    ];
    for (final text in forbidden) {
      recorder.record(VoiceDiagnosticEvent.fromCode(text),
          desired: VoiceDiagnosticLanguage.fromValue(text),
          applied: VoiceDiagnosticLanguage.fromValue(text));
    }
    final snapshot = await invoke(
        VoiceLanguageDiagnosticsExtensions.snapshotMethod, {
      for (final text in forbidden) text: text,
      'expression': forbidden.join()
    });
    expect(snapshot.keys.toSet(), {'schemaVersion', 'dropped', 'events'});
    expect(snapshot['schemaVersion'], 2);
    final events = snapshot['events'] as List;
    for (final event in events) {
      expect((event as Map).keys.toSet(), {
        'sequence',
        'elapsedMs',
        'event',
        'attempt',
        'generation',
        'revision',
        'desired',
        'applied',
        'pending',
        'channelOpen',
        'baselineReady',
        'failure',
      });
    }
    for (final event in events.skip(1)) {
      expect(event['event'], 'unknown');
      expect(event['desired'], 'unknown');
      expect(event['applied'], 'unknown');
    }
    for (final text in forbidden) {
      expect(recorder.snapshot(), isNot(contains(text)));
      expect(jsonEncode(snapshot), isNot(contains(text)));
    }
  });

  test(
      'registration is idempotent; clear, stop, restart and dispose are isolated',
      () async {
    recorder.startCapture();
    recorder.startCapture();
    expect(handlers, hasLength(2));
    expect(
        (await invoke(
            VoiceLanguageDiagnosticsExtensions.snapshotMethod))['events'],
        [isA<Map>().having((m) => m['event'], 'event', 'capture_ready')]);
    expect(await invoke(VoiceLanguageDiagnosticsExtensions.clearMethod),
        jsonDecode(VoiceLanguageDiagnostics.emptySnapshot));
    recorder.record(VoiceDiagnosticEvent.applied, generation: 1);
    recorder.stopCapture();
    recorder.record(VoiceDiagnosticEvent.rejected, generation: 1);
    expect(recorder.snapshot(), VoiceLanguageDiagnostics.emptySnapshot);
    recorder.startCapture();
    recorder.record(VoiceDiagnosticEvent.send, generation: 2);
    final next = VoiceLanguageDiagnostics.forTesting(extensions: bridge);
    next.startCapture();
    recorder.record(VoiceDiagnosticEvent.rejected);
    recorder.dispose();
    recorder.dispose();
    recorder.startCapture();
    expect(recorder.snapshot(), VoiceLanguageDiagnostics.emptySnapshot);
    final snapshot =
        await invoke(VoiceLanguageDiagnosticsExtensions.snapshotMethod);
    expect((snapshot['events'] as List).single['event'], 'capture_ready');
    next.dispose();
    expect(await invoke(VoiceLanguageDiagnosticsExtensions.snapshotMethod),
        jsonDecode(VoiceLanguageDiagnostics.emptySnapshot));
  });

  test('v2 baseline field and fixed failure mapping survive clear and dispose',
      () async {
    recorder.startCapture();
    for (final (event, ready, failure) in [
      (VoiceDiagnosticEvent.baselineWaiting, false, 'none'),
      (VoiceDiagnosticEvent.baselineTimeout, false, 'timeout'),
      (VoiceDiagnosticEvent.baselineReady, true, 'none'),
    ]) {
      recorder.record(event, baselineReady: ready);
      final snapshot =
          await invoke(VoiceLanguageDiagnosticsExtensions.snapshotMethod);
      expect(snapshot['schemaVersion'], 2);
      final row = (snapshot['events'] as List).last;
      expect(row['baselineReady'], ready);
      expect(row['failure'], failure);
      expect(utf8.encode(jsonEncode(row)).length, lessThanOrEqualTo(512));
    }
    expect(
        (await invoke(
            VoiceLanguageDiagnosticsExtensions.clearMethod))['schemaVersion'],
        2);
    recorder.record(VoiceDiagnosticEvent.send, baselineReady: true);
    expect(
        (jsonDecode(recorder.snapshot())['events'] as List)
            .single['baselineReady'],
        isTrue);
    recorder.dispose();
    expect(await invoke(VoiceLanguageDiagnosticsExtensions.snapshotMethod),
        {'schemaVersion': 2, 'dropped': 0, 'events': []});
  });

  test('registration failures cannot escape; failed registration can retry',
      () {
    var fails = true;
    var calls = 0;
    final bridge = VoiceLanguageDiagnosticsExtensions.forTesting((_, __) {
      calls++;
      if (fails) throw StateError('PRIVATE_ERROR_SENTINEL');
    });
    final recorder = VoiceLanguageDiagnostics.forTesting(extensions: bridge);
    expect(recorder.startCapture, returnsNormally);
    expect(calls, 2);
    expect(recorder.snapshot(), isNot(contains('PRIVATE_ERROR_SENTINEL')));
    fails = false;
    recorder.startCapture();
    recorder.startCapture();
    expect(calls, 4);
    recorder.dispose();
  });
}
