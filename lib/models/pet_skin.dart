/// 寵物外觀（換皮）。CR-0011：長者可以把陪伴夥伴換成不同動物，
/// 預設為狗狗，外觀只影響顯示圖片，不影響任何陪伴 / 記憶 / Care Alert 邏輯。
enum PetSkin {
  dog,
  guineaPig,
  fox,
}

extension PetSkinX on PetSkin {
  /// 存進本機（SharedPreferences）用的穩定字串。
  /// 刻意不直接用 `enum.name`，避免之後改 enum 名稱時對不上既有存檔。
  String get storageId => switch (this) {
        PetSkin.dog => 'dog',
        PetSkin.guineaPig => 'guinea_pig',
        PetSkin.fox => 'fox',
      };

  /// 圖片檔名前綴，對應 `assets/pets/<資料夾>/<prefix>_*.png`。
  String get assetPrefix => switch (this) {
        PetSkin.dog => 'dog',
        PetSkin.guineaPig => 'guinea_pig',
        PetSkin.fox => 'fox',
      };

  /// 給長者看的中文名稱。
  String get label => switch (this) {
        PetSkin.dog => '狗狗',
        PetSkin.guineaPig => '天竺鼠',
        PetSkin.fox => '狐狸',
      };

  /// 從存檔字串還原；認不得（含 null / 舊資料）一律回預設狗狗，永不 crash。
  static PetSkin fromStorageId(String? id) {
    return switch (id) {
      'guinea_pig' => PetSkin.guineaPig,
      'fox' => PetSkin.fox,
      _ => PetSkin.dog,
    };
  }
}
