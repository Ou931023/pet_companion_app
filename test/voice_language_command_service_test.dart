import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/models/language_route.dart';
import 'package:pet_companion_app/services/voice_language_command_service.dart';

void main() {
  const parser = VoiceLanguageCommandService();
  for (final command in [
    '請用台語陪我聊天',
    '改成台語',
    '切換到臺語',
    '來講台語',
    '麻煩你幫我改用台語回答好嗎',
    '请用台语跟我说话',
    '幫我設定成台語',
    '把聊天語言改成台語',
    '改說台語',
    '把語言改成台語',
  ]) {
    test('explicit Taiwanese command: $command', () {
      expect(parser.parse(command), VoiceLanguageMode.taigiRealtime);
    });
  }
  for (final command in ['改用國語', '用中文回答', '請切換成華語', '現在用國語說話。', '請用國語跟我說話']) {
    test('explicit Mandarin command: $command', () {
      expect(parser.parse(command), VoiceLanguageMode.defaultOpenAiRealtime);
    });
  }
  for (final text in [
    '台語',
    '播放台語歌曲',
    '我想聽台語歌',
    '找台語新聞',
    '我喜歡台語',
    '不要切換台語',
    '不要用中文',
    '不是叫你用台語',
    '你會說台語嗎？',
    '他說改用台語',
    '「改用台語」',
    '請說「改用國語」',
    '如果我說改用台語呢',
    '改用台語或國語',
    '先用台語再用中文',
    '用台語唱歌',
    '用中文搜尋台語新聞',
    '今天心情很好',
    '',
    '改用台語，不要真的切換',
  ]) {
    test('does not switch for mention or ambiguous request: $text', () {
      expect(parser.parse(text), isNull);
    });
  }
}
