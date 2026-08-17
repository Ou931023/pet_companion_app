import '../models/pet_skin.dart';
import '../models/pet_status.dart';
import '../models/pet_visual_profile.dart';

/// 寵物圖片路徑組裝。CR-0011：改為依 [PetSkin] 動態組路徑，
/// 讓狗狗 / 天竺鼠 / 狐狸共用同一套狀態邏輯，只換檔名前綴。
///
/// 實際素材（Step 1 整理）：
/// - dog：talk 6 / rest 3 / listening 1 / states 8
/// - guineaPig：talk 3 / rest 3 / listening 1 / states 8
/// - fox：talk 6 / rest 3 / listening 1 / states 8
/// - mochi：talk 6 / rest 3 / listening 1 / states 8
class AssetPaths {
  const AssetPaths._();

  /// PetMode → states 檔名尾碼。多個情緒共用同一張（thinking→normal、
  /// concerned→caring、smile→happy），與既有 dog 行為一致。
  static const Map<PetMode, String> _stateSuffix = {
    PetMode.normal: 'normal',
    PetMode.thinking: 'normal',
    PetMode.caring: 'caring',
    PetMode.concerned: 'caring',
    PetMode.happy: 'happy',
    PetMode.smile: 'happy',
    PetMode.excited: 'excited',
    PetMode.thirsty: 'thirsty',
    PetMode.sleepy: 'sleepy',
    PetMode.hungry: 'hungry',
    PetMode.sad: 'sad',
  };

  /// v2 半寫實狗狗目前已通過候選 QA 的 state 子集。
  ///
  /// 只宣告已實際存在且可被 Flutter asset bundle 打包的檔案；其餘狀態
  /// 會 fallback 到既有 v1 Q 版素材，避免正式版顯示不存在的圖片。
  static const Map<PetMode, String> _realisticDogStateSuffix = {
    PetMode.normal: 'normal',
    PetMode.thinking: 'normal',
    PetMode.caring: 'caring',
    PetMode.concerned: 'caring',
    PetMode.happy: 'happy',
    PetMode.smile: 'happy',
    PetMode.excited: 'excited',
    PetMode.thirsty: 'thirsty',
    PetMode.sleepy: 'sleepy',
    PetMode.hungry: 'hungry',
    PetMode.sad: 'sad',
  };

  /// 現有 production 圖包的素材能力宣告。
  ///
  /// 目前全部是 Q 版、成年素材；未來真實版 / 幼年素材進來時，優先擴充這裡，
  /// 不要讓 frame 數與 fallback 規則散落在 UI。
  static const Map<PetSkin, PetVisualProfile> _profiles = {
    PetSkin.dog: PetVisualProfile(
      skin: PetSkin.dog,
      visualStyle: PetVisualStyle.cute,
      growthStage: PetGrowthStage.adult,
      talkFrameCount: 6,
      restFrameCount: 3,
      stateSuffixes: _stateSuffix,
    ),
    PetSkin.guineaPig: PetVisualProfile(
      skin: PetSkin.guineaPig,
      visualStyle: PetVisualStyle.cute,
      growthStage: PetGrowthStage.adult,
      talkFrameCount: 3,
      restFrameCount: 3,
      stateSuffixes: _stateSuffix,
    ),
    PetSkin.fox: PetVisualProfile(
      skin: PetSkin.fox,
      visualStyle: PetVisualStyle.cute,
      growthStage: PetGrowthStage.adult,
      talkFrameCount: 6,
      restFrameCount: 3,
      stateSuffixes: _stateSuffix,
    ),
    PetSkin.mochi: PetVisualProfile(
      skin: PetSkin.mochi,
      visualStyle: PetVisualStyle.cute,
      growthStage: PetGrowthStage.adult,
      talkFrameCount: 6,
      restFrameCount: 3,
      stateSuffixes: _stateSuffix,
    ),
  };

  /// 最終保底圖（第二層 fallback）：永遠存在的狗狗 rest_01。
  /// 也供登入頁 / 新手導覽頁當預設寵物圖，避免硬寫路徑字串。
  static const String defaultRestImage = 'assets/pets/rest/dog_rest_01.png';

  static String _padded(int i) => i.toString().padLeft(2, '0');

  /// 取得單一外觀目前的素材能力。認不得時保底狗狗規格。
  static PetVisualProfile visualProfile(PetSkin skin) =>
      _profiles[skin] ?? _profiles[PetSkin.dog]!;

  /// 取得所有 production-ready 寵物素材規格，供測試與未來後台偏好追蹤使用。
  static List<PetVisualProfile> get productionProfiles =>
      [for (final skin in PetSkin.values) visualProfile(skin)];

  /// 目前已可提供 v2 半寫實靜態狀態素材的寵物。
  ///
  /// 注意：這不是完整 production profile，因為 talk/rest/listening 尚未補齊。
  /// UI 若要開放切換，需要用此方法判斷是否能顯示「真實版」選項。
  static bool supportsVisualStyle(
    PetSkin skin,
    PetVisualStyle visualStyle, {
    PetGrowthStage growthStage = PetGrowthStage.adult,
  }) {
    if (visualStyle == PetVisualStyle.cute) return true;
    return skin == PetSkin.dog &&
        visualStyle == PetVisualStyle.realistic &&
        growthStage == PetGrowthStage.adult;
  }

  static List<PetVisualStyle> availableVisualStyles(
    PetSkin skin, {
    PetGrowthStage growthStage = PetGrowthStage.adult,
  }) =>
      [
        PetVisualStyle.cute,
        if (supportsVisualStyle(
          skin,
          PetVisualStyle.realistic,
          growthStage: growthStage,
        ))
          PetVisualStyle.realistic,
      ];

  /// 說話動畫每一張（張數依 [skin]，guineaPig 只有 3 張）。
  static List<String> talkingFrames(PetSkin skin) {
    final count = visualProfile(skin).talkFrameCount;
    return [
      for (var i = 1; i <= count; i++)
        'assets/pets/talk/${skin.assetPrefix}_talk_${_padded(i)}.png',
    ];
  }

  /// v2 visual-style-aware talking frame resolver.
  ///
  /// 目前僅 dog / realistic / adult 有 6 張基本 talking frames；其他組合回 v1。
  static List<String> talkingFramesForStyle(
    PetSkin skin, {
    PetVisualStyle visualStyle = PetVisualStyle.cute,
    PetGrowthStage growthStage = PetGrowthStage.adult,
  }) {
    if (skin == PetSkin.dog &&
        visualStyle == PetVisualStyle.realistic &&
        growthStage == PetGrowthStage.adult) {
      return [
        for (var i = 1; i <= 6; i++)
          'assets/pets/v2/realistic/adult/dog/talk/talk_${_padded(i)}.png',
      ];
    }
    return talkingFrames(skin);
  }

  /// 休息（待機）動畫每一張。
  static List<String> restFrames(PetSkin skin) {
    final count = visualProfile(skin).restFrameCount;
    return [
      for (var i = 1; i <= count; i++)
        'assets/pets/rest/${skin.assetPrefix}_rest_${_padded(i)}.png',
    ];
  }

  /// v2 visual-style-aware rest frame resolver.
  ///
  /// 目前僅 dog / realistic / adult 有 3 張基本 rest frames；其他組合回 v1。
  static List<String> restFramesForStyle(
    PetSkin skin, {
    PetVisualStyle visualStyle = PetVisualStyle.cute,
    PetGrowthStage growthStage = PetGrowthStage.adult,
  }) {
    if (skin == PetSkin.dog &&
        visualStyle == PetVisualStyle.realistic &&
        growthStage == PetGrowthStage.adult) {
      return [
        for (var i = 1; i <= 3; i++)
          'assets/pets/v2/realistic/adult/dog/rest/rest_${_padded(i)}.png',
      ];
    }
    return restFrames(skin);
  }

  /// 正在聆聽（單張）。
  static String listening(PetSkin skin) =>
      'assets/pets/listening/${skin.assetPrefix}_listening.png';

  /// v2 visual-style-aware listening resolver.
  ///
  /// 目前僅 dog / realistic / adult 有 listening 圖；其他組合回 v1。
  static String listeningForStyle(
    PetSkin skin, {
    PetVisualStyle visualStyle = PetVisualStyle.cute,
    PetGrowthStage growthStage = PetGrowthStage.adult,
  }) {
    if (skin == PetSkin.dog &&
        visualStyle == PetVisualStyle.realistic &&
        growthStage == PetGrowthStage.adult) {
      return 'assets/pets/v2/realistic/adult/dog/listening/listening.png';
    }
    return listening(skin);
  }

  /// 依情緒狀態取靜態圖。
  static String stateImage(PetSkin skin, PetMode mode) {
    final suffix = visualProfile(skin).stateSuffixFor(mode);
    return 'assets/pets/states/${skin.assetPrefix}_$suffix.png';
  }

  /// v2 visual-style-aware 靜態圖 resolver。
  ///
  /// - Q 版：維持既有 v1 路徑。
  /// - 真實版：目前僅 dog / adult / normal-happy-caring-sad 子集走 v2。
  /// - 缺素材：立即 fallback 到 v1，正式版不顯示破圖。
  static String stateImageForStyle(
    PetSkin skin,
    PetMode mode, {
    PetVisualStyle visualStyle = PetVisualStyle.cute,
    PetGrowthStage growthStage = PetGrowthStage.adult,
  }) {
    if (skin == PetSkin.dog &&
        visualStyle == PetVisualStyle.realistic &&
        growthStage == PetGrowthStage.adult) {
      final suffix = _realisticDogStateSuffix[mode];
      if (suffix != null) {
        return 'assets/pets/v2/realistic/adult/dog/states/$suffix.png';
      }
    }
    return stateImage(skin, mode);
  }

  /// 該外觀的第一層 fallback：自己的 rest_01。
  static String skinRestPrimary(PetSkin skin) =>
      'assets/pets/rest/${skin.assetPrefix}_rest_01.png';
}
