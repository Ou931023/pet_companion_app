import '../models/voice_agent_state.dart';

/// 依語音狀態決定首頁語音按鈕的文字（連續 Realtime session 模型）。
///
/// 純函式、無副作用，方便單元測試直接驗證「每個狀態對應的白話按鈕文字」。
/// 對應的輪次規則：
/// - idle：可以開始說話。
/// - connecting：連線中，請稍候。
/// - ready / listening：寵物待命聆聽，使用者可直接開口。
/// - transcribing：正在把使用者剛說的話轉成文字。
/// - thinking：寵物正在想 / 處理工具。
/// - speaking：寵物正在說話；想換自己講可以點按鈕打斷。
/// - recovering：連線中斷、重新連線中。
/// - error：發生錯誤，可重試。
///
/// 文字一律白話、不出現工程字；speaking / thinking 帶入寵物名字（[petName]）讓提示更親切。
String realtimeVoiceButtonLabel(
  VoiceAgentState state, {
  required String petName,
  required bool taigiRealtime,
}) {
  final name = petName.trim().isEmpty ? '我' : petName.trim();
  switch (state) {
    case VoiceAgentState.idle:
      return taigiRealtime ? '用台語跟我聊聊' : '想聊天就點我';
    case VoiceAgentState.connecting:
      return '正在連線，馬上就好';
    case VoiceAgentState.ready:
    case VoiceAgentState.listening:
      return '我在聽，你說';
    case VoiceAgentState.transcribing:
      return '正在聽你說';
    case VoiceAgentState.thinking:
      return '$name正在想，等一下';
    case VoiceAgentState.speaking:
      return '$name正在說，想說話點我';
    case VoiceAgentState.recovering:
      return '正在重新連線';
    case VoiceAgentState.error:
      return '連線怪怪的，點我再試一次';
  }
}
