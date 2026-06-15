import '../models/pet_skin.dart';
import '../models/pet_status.dart';

/// 寵物圖片路徑組裝。CR-0011：改為依 [PetSkin] 動態組路徑，
/// 讓狗狗 / 天竺鼠 / 狐狸共用同一套狀態邏輯，只換檔名前綴。
///
/// 實際素材（Step 1 整理）：
/// - dog：talk 6 / rest 3 / listening 1 / states 8
/// - guineaPig：talk 3 / rest 3 / listening 1 / states 8
/// - fox：talk 6 / rest 3 / listening 1 / states 8
/// - ferret：talk 6 / rest 3 / listening 1 / states 8
/// - mochi：talk 6 / rest 3 / listening 1 / states 8
class AssetPaths {
  const AssetPaths._();

  /// 每個外觀實際擁有的 talk 動畫張數（依素材，不可亂猜，否則會抓到不存在的檔）。
  static const Map<PetSkin, int> _talkFrameCount = {
    PetSkin.dog: 6,
    PetSkin.guineaPig: 3,
    PetSkin.fox: 6,
    PetSkin.ferret: 6,
    PetSkin.mochi: 6,
  };

  /// 每個外觀實際擁有的 rest 動畫張數。
  static const Map<PetSkin, int> _restFrameCount = {
    PetSkin.dog: 3,
    PetSkin.guineaPig: 3,
    PetSkin.fox: 3,
    PetSkin.ferret: 3,
    PetSkin.mochi: 3,
  };

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

  /// 最終保底圖（第二層 fallback）：永遠存在的狗狗 rest_01。
  /// 也供登入頁 / 新手導覽頁當預設寵物圖，避免硬寫路徑字串。
  static const String defaultRestImage = 'assets/pets/rest/dog_rest_01.png';

  static String _padded(int i) => i.toString().padLeft(2, '0');

  /// 說話動畫每一張（張數依 [skin]，guineaPig 只有 3 張）。
  static List<String> talkingFrames(PetSkin skin) {
    final count = _talkFrameCount[skin] ?? 1;
    return [
      for (var i = 1; i <= count; i++)
        'assets/pets/talk/${skin.assetPrefix}_talk_${_padded(i)}.png',
    ];
  }

  /// 休息（待機）動畫每一張。
  static List<String> restFrames(PetSkin skin) {
    final count = _restFrameCount[skin] ?? 1;
    return [
      for (var i = 1; i <= count; i++)
        'assets/pets/rest/${skin.assetPrefix}_rest_${_padded(i)}.png',
    ];
  }

  /// 正在聆聽（單張）。
  static String listening(PetSkin skin) =>
      'assets/pets/listening/${skin.assetPrefix}_listening.png';

  /// 依情緒狀態取靜態圖。
  static String stateImage(PetSkin skin, PetMode mode) {
    final suffix = _stateSuffix[mode] ?? 'normal';
    return 'assets/pets/states/${skin.assetPrefix}_$suffix.png';
  }

  /// 該外觀的第一層 fallback：自己的 rest_01。
  static String skinRestPrimary(PetSkin skin) =>
      'assets/pets/rest/${skin.assetPrefix}_rest_01.png';
}
