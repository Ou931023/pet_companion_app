import '../models/voice_agent_state.dart';

/// 依語音狀態決定首頁語音按鈕的文字（turn-based「一人一句」輪次模型）。
///
/// 純函式、無副作用，方便單元測試直接驗證「每個狀態對應的白話按鈕文字」。
/// 對應的輪次規則：
/// - idle：等使用者按鈕，按一下就能說這一句。
/// - connecting：連線中，請稍候。
/// - ready / listening / transcribing：正在聽使用者說這一句。
/// - thinking：寵物正在想 / 處理工具（此時不接受新語音）。
/// - speaking：寵物正在說話（不可打斷，先聽完）。
/// - recovering：連線中斷、重新連線中。
/// - error：發生錯誤，可重試。
///
/// 文字一律白話、不出現工程字（state / realtime / session / VAD …）；
/// thinking / speaking 帶入寵物名字（[petName]），沒有名字時退回「咕咕」讓提示仍親切。
String realtimeVoiceButtonLabel(
  VoiceAgentState state, {
  required String petName,
  required bool taigiRealtime,
}) {
  final name = petName.trim().isEmpty ? '咕咕' : petName.trim();
  switch (state) {
    case VoiceAgentState.idle:
      return taigiRealtime ? '用台語按住說話' : '按住說話';
    case VoiceAgentState.connecting:
      return '正在連線，馬上就好';
    case VoiceAgentState.ready:
    case VoiceAgentState.listening:
    case VoiceAgentState.transcribing:
      // CR-0096：聆聽中按一下＝停止收音並送出本輪語音，文案明說「說完再按一下」，
      // 讓長者知道吵雜環境也能自己決定何時結束說話。
      return '正在聽你說，說完再按一下';
    case VoiceAgentState.thinking:
      return '$name想一下';
    case VoiceAgentState.speaking:
      return '$name正在說話';
    case VoiceAgentState.recovering:
      return '正在重新連線';
    case VoiceAgentState.error:
      return '再試一次';
  }
}
