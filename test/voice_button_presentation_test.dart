import 'package:flutter_test/flutter_test.dart';

import 'package:pet_companion_app/models/voice_agent_state.dart';
import 'package:pet_companion_app/utils/voice_button_presentation.dart';

void main() {
  group('realtimeVoiceButtonLabel 依語音狀態顯示白話按鈕文字', () {
    String label(VoiceAgentState state, {bool taigi = false}) =>
        realtimeVoiceButtonLabel(state, petName: '咕咕', taigiRealtime: taigi);

    test('idle：按住說話', () {
      expect(label(VoiceAgentState.idle), '按住說話');
    });

    test('idle 台語模式：顯示台語邀請', () {
      expect(label(VoiceAgentState.idle, taigi: true), '用台語按住說話');
    });

    test('connecting：連線中提示', () {
      expect(label(VoiceAgentState.connecting), '正在連線，馬上就好');
    });

    test('listening：正在聽你說這一句', () {
      expect(label(VoiceAgentState.listening), '正在聽你說');
      expect(label(VoiceAgentState.ready), '正在聽你說');
    });

    test('transcribing：正在把使用者的話轉文字', () {
      expect(label(VoiceAgentState.transcribing), '正在聽你說');
    });

    test('thinking：寵物正在想（帶寵物名字）', () {
      expect(label(VoiceAgentState.thinking), '咕咕想一下');
    });

    test('speaking：寵物正在說話（不可打斷，先聽完）', () {
      expect(label(VoiceAgentState.speaking), '咕咕正在說話');
    });

    test('recovering：重新連線中', () {
      expect(label(VoiceAgentState.recovering), '正在重新連線');
    });

    test('error：可重試', () {
      expect(label(VoiceAgentState.error), '再試一次');
    });

    test('沒有任何工程字 / debug 字樣（state/realtime/session/VAD …）', () {
      for (final state in VoiceAgentState.values) {
        final text = label(state);
        expect(text, isNotEmpty);
        final lower = text.toLowerCase();
        for (final banned in [
          'error',
          'state',
          'realtime',
          'session',
          'response.cancel',
          'vad',
        ]) {
          expect(lower, isNot(contains(banned)));
        }
        expect(text, isNot(contains('null')));
      }
    });

    test('寵物名字為空時退回「咕咕」，不會出現空字串拼接', () {
      final text = realtimeVoiceButtonLabel(
        VoiceAgentState.speaking,
        petName: '   ',
        taigiRealtime: false,
      );
      expect(text, '咕咕正在說話');
    });
  });
}
