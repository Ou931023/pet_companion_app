import '../models/language_route.dart';
import '../utils/zh_convert.dart';

/// Deliberately accepts whole commands, not language mentions in conversation.
class VoiceLanguageCommandService {
  const VoiceLanguageCommandService();

  VoiceLanguageMode? parse(String text) {
    final normalized = toTraditional(text.trim())
        .replaceAll('臺語', '台語')
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[，,]'), '')
        .replaceFirst(RegExp(r'[。！!？?]+$'), '');
    final match = RegExp(
      r'^(?:請|麻煩)?(?:可不可以|能不能|可以|能)?(?:你)?(?:幫我)?(?:以後|接下來|之後|現在)?'
      r'(?:把(?:聊天)?語言)?'
      r'(?:設定成|設定為|設成|改成|改用|改講|改說|切換成|切換到|切換為|切換|換成|換用|用|講|說|來講)'
      r'(台語|國語|中文|華語)'
      r'(?:(?:跟我|和我|陪我)?(?:說話|聊天|講話|回答|回覆))?(?:好嗎|可以嗎|嗎|吧)?$',
    ).firstMatch(normalized);
    if (match == null) return null;
    return match.group(1) == '台語'
        ? VoiceLanguageMode.taigiRealtime
        : VoiceLanguageMode.defaultOpenAiRealtime;
  }
}
