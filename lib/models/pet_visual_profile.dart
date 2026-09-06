import 'pet_skin.dart';
import 'pet_status.dart';

/// 寵物視覺風格。正式素材目前都是 Q 版；先把資料模型立起來，
/// 後續真實版 A/B preference 可以沿用同一欄位，不必再改事件與後台契約。
enum PetVisualStyle {
  cute,
  realistic,
}

extension PetVisualStyleX on PetVisualStyle {
  String get storageId => switch (this) {
        PetVisualStyle.cute => 'cute',
        PetVisualStyle.realistic => 'realistic',
      };

  String get label => switch (this) {
        PetVisualStyle.cute => 'Q版',
        PetVisualStyle.realistic => '真實版',
      };

  static PetVisualStyle fromStorageId(String? id) {
    return switch (id) {
      'realistic' => PetVisualStyle.realistic,
      _ => PetVisualStyle.cute,
    };
  }
}

/// 寵物成長階段。現有素材先標示為 adult；未來新增 baby / young 圖包時，
/// 可以在不改 [PetSkin] 的前提下擴充。
enum PetGrowthStage {
  baby,
  young,
  adult,
}

extension PetGrowthStageX on PetGrowthStage {
  String get storageId => switch (this) {
        PetGrowthStage.baby => 'baby',
        PetGrowthStage.young => 'young',
        PetGrowthStage.adult => 'adult',
      };

  String get label => switch (this) {
        PetGrowthStage.baby => '幼年',
        PetGrowthStage.young => '成長中',
        PetGrowthStage.adult => '成年',
      };

  static PetGrowthStage fromStorageId(String? id) {
    return switch (id) {
      'baby' => PetGrowthStage.baby,
      'young' => PetGrowthStage.young,
      _ => PetGrowthStage.adult,
    };
  }
}

/// 單一寵物外觀的素材能力宣告。
///
/// 用途：
/// - App：知道目前外觀有哪些動畫張數與 fallback state。
/// - Tracking：事件可帶出 skin / visualStyle / growthStage，後台才知道偏好。
/// - 素材驗收：未來新增真實版或幼年素材時，用測試檢查圖包是否完整。
class PetVisualProfile {
  const PetVisualProfile({
    required this.skin,
    required this.visualStyle,
    required this.growthStage,
    required this.talkFrameCount,
    required this.restFrameCount,
    required this.stateSuffixes,
    this.isProductionPreferred = false,
  });

  final PetSkin skin;
  final PetVisualStyle visualStyle;
  final PetGrowthStage growthStage;
  final int talkFrameCount;
  final int restFrameCount;
  final bool isProductionPreferred;

  /// PetMode 對應到 `assets/pets/states/<skin>_<suffix>.png` 的 suffix。
  final Map<PetMode, String> stateSuffixes;

  bool get isProductionReady =>
      talkFrameCount > 0 &&
      restFrameCount > 0 &&
      growthStage == PetGrowthStage.adult;

  String stateSuffixFor(PetMode mode) => stateSuffixes[mode] ?? 'normal';

  Map<String, Object> toTrackingMetadata() => {
        'petType': skin.storageId,
        'visualStyle': visualStyle.storageId,
        'growthStage': growthStage.storageId,
        'talkFrameCount': talkFrameCount,
        'restFrameCount': restFrameCount,
      };
}
