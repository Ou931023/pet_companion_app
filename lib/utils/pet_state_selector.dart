import '../models/pet_status.dart';

/// CR-0088：寵物「顯示狀態」選擇器（純函式，無 UI / 無計時器）。
///
/// 背景：先前首頁幾乎只在 `listening` / `talking` 之間切換，其他 states 圖很少出現。
/// 本選擇器把「現在該顯示哪個 PetMode」集中成一個純函式，由首頁在 build 時呼叫，
/// 消費既有訊號（語音狀態、寵物數值、短暫情緒），**不改 Realtime 主流程、不改控制器內部**。
///
/// 優先序（高 → 低）：
/// 1. listening：麥克風正在收音（使用者說話中）。
/// 2. talking：寵物正在播放語音。
/// 3. transient：互動剛結束的短暫情緒（happy / caring / sad…，由 PetController 持有計時）。
/// 4. care state：由寵物數值推得（飽足度低 → hungry、心情低 → sad、親密度低 → caring、
///    深夜 → sleepy）。資料缺漏不硬觸發。
/// 5. rest：以上皆非時的閒置待機（rest frames 輪播）。
class PetStateSelector {
  const PetStateSelector._();

  static const int satietyThreshold = 30;
  static const int moodThreshold = 30;
  static const int intimacyThreshold = 30;

  /// 預設短暫情緒顯示時間（互動結束後顯示幾秒再退場）。
  static const Duration transientDuration = Duration(seconds: 4);

  /// 主選擇：依優先序決定要顯示的 [PetMode]。
  ///
  /// - [isMicCapturing]：麥克風正在收音（voiceState listening/transcribing）。
  /// - [isPetSpeaking]：寵物語音正在播放（voiceState speaking 或既有 talking 模式）。
  /// - [transientMode]：短暫情緒（[PetController.transientMode]），無則 null。
  /// - [satiety]/[mood]/[intimacy]：寵物數值 0..100，未知傳 null（不硬觸發）。
  /// - [hour]：當地小時（0..23），用於深夜 sleepy；未知傳 null。
  static PetMode select({
    required bool isMicCapturing,
    required bool isPetSpeaking,
    PetMode? transientMode,
    int? satiety,
    int? mood,
    int? intimacy,
    int? hour,
  }) {
    if (isMicCapturing) return PetMode.listening;
    if (isPetSpeaking) return PetMode.talking;
    if (transientMode != null) return transientMode;
    final care = careStateFor(
      satiety: satiety,
      mood: mood,
      intimacy: intimacy,
      hour: hour,
    );
    if (care != null) return care;
    return PetMode.rest;
  }

  /// 由寵物數值推得「照護狀態」。皆無命中回 null（→ 交回 rest）。
  ///
  /// 只接目前真實存在的數值（satiety / mood / intimacy）與時鐘（深夜）；
  /// 沒有 hydration / energy 資料 → 不硬觸發 thirsty / 由感測推得的 sleepy。
  static PetMode? careStateFor({
    int? satiety,
    int? mood,
    int? intimacy,
    int? hour,
  }) {
    if (satiety != null && satiety < satietyThreshold) return PetMode.hungry;
    if (mood != null && mood < moodThreshold) return PetMode.sad;
    if (intimacy != null && intimacy < intimacyThreshold) return PetMode.caring;
    if (hour != null && (hour >= 22 || hour < 6)) return PetMode.sleepy;
    return null;
  }

  /// 對話情緒標籤 → 短暫情緒 PetMode（neutral / 未知 → null，不觸發）。
  /// 對齊 ConversationTurn.emotionTag 的值（happy/sad/lonely/anxious/tired/angry/neutral）。
  static PetMode? transientModeForEmotion(String? emotionTag) {
    return switch (emotionTag) {
      'happy' => PetMode.happy,
      'excited' => PetMode.excited,
      'sad' => PetMode.sad,
      'lonely' => PetMode.caring,
      'anxious' => PetMode.caring,
      'tired' => PetMode.sleepy,
      'angry' => PetMode.caring,
      _ => null,
    };
  }
}
