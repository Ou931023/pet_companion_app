import 'package:flutter_test/flutter_test.dart';

import 'package:pet_companion_app/models/voice_agent_state.dart';
import 'package:pet_companion_app/utils/voice_button_presentation.dart';

void main() {
  group('realtimeVoiceButtonLabel 依語音狀態顯示白話按鈕文字', () {
    String label(VoiceAgentState state, {bool taigi = false}) =>
        realtimeVoiceButtonLabel(state, petName: '咕咕', taigiRealtime: taigi);

    test('idle：可以開始說話', () {
      expect(label(VoiceAgentState.idle), '想聊天就點我');
    });

    test('idle 台語模式：顯示台語邀請', () {
      expect(label(VoiceAgentState.idle, taigi: true), '用台語跟我聊聊');
    });

    test('connecting：連線中提示', () {
      expect(label(VoiceAgentState.connecting), '正在連線，馬上就好');
    });

    test('listening：待命聆聽，使用者可開口', () {
      expect(label(VoiceAgentState.listening), '我在聽，你說');
      expect(label(VoiceAgentState.ready), '我在聽，你說');
    });

    test('transcribing：正在把使用者的話轉文字', () {
      expect(label(VoiceAgentState.transcribing), '正在聽你說');
    });

    test('thinking：寵物正在想（帶寵物名字）', () {
      expect(label(VoiceAgentState.thinking), '咕咕正在想，等一下');
    });

    test('speaking：寵物正在說，並提示可點按鈕換自己說', () {
      expect(label(VoiceAgentState.speaking), '咕咕正在說，想說話點我');
    });

    test('recovering：重新連線中', () {
      expect(label(VoiceAgentState.recovering), '正在重新連線');
    });

    test('error：可重試', () {
      expect(label(VoiceAgentState.error), '連線怪怪的，點我再試一次');
    });

    test('沒有任何工程字 / debug 字樣', () {
      for (final state in VoiceAgentState.values) {
        final text = label(state);
        expect(text, isNotEmpty);
        expect(text.toLowerCase(), isNot(contains('error')));
        expect(text.toLowerCase(), isNot(contains('state')));
        expect(text, isNot(contains('null')));
      }
    });

    test('寵物名字為空時退回「我」，不會出現空字串拼接', () {
      final text = realtimeVoiceButtonLabel(
        VoiceAgentState.speaking,
        petName: '   ',
        taigiRealtime: false,
      );
      expect(text, '我正在說，想說話點我');
    });
  });
}
