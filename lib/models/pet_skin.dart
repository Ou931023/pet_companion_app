/// 寵物外觀（換皮）。CR-0011：長者可以把陪伴夥伴換成不同動物，
/// 預設為狗狗，外觀只影響顯示圖片，不影響任何陪伴 / 記憶 / Care Alert 邏輯。
enum PetSkin {
  dog,
  guineaPig,
  fox,
  ferret,
  mochi,
}

extension PetSkinX on PetSkin {
  /// 存進本機（SharedPreferences）用的穩定字串。
  /// 刻意不直接用 `enum.name`，避免之後改 enum 名稱時對不上既有存檔。
  String get storageId => switch (this) {
        PetSkin.dog => 'dog',
        PetSkin.guineaPig => 'guinea_pig',
        PetSkin.fox => 'fox',
        PetSkin.ferret => 'ferret',
        PetSkin.mochi => 'mochi',
      };

  /// 圖片檔名前綴，對應 `assets/pets/<資料夾>/<prefix>_*.png`。
  String get assetPrefix => switch (this) {
        PetSkin.dog => 'dog',
        PetSkin.guineaPig => 'guinea_pig',
        PetSkin.fox => 'fox',
        PetSkin.ferret => 'ferret',
        PetSkin.mochi => 'mochi',
      };

  /// 給長者看的中文名稱。
  String get label => switch (this) {
        PetSkin.dog => '狗狗',
        PetSkin.guineaPig => '天竺鼠',
        PetSkin.fox => '狐狸',
        PetSkin.ferret => '雪貂',
        PetSkin.mochi => '麻吉',
      };

  /// 一句話特色描述（純呈現，僅用於外觀選擇器，不影響任何陪伴邏輯）。
  String get tagline => switch (this) {
        PetSkin.dog => '溫暖陪伴型',
        PetSkin.guineaPig => '可愛療癒型',
        PetSkin.fox => '活潑聰明型',
        PetSkin.ferret => '好奇靈巧型',
        PetSkin.mochi => '黏人撒嬌型',
      };

  /// 解鎖需要的金幣數（沿用既有 wallet / coins）。狗狗預設已擁有，免費。
  int get unlockCost => switch (this) {
        PetSkin.dog => 0,
        PetSkin.guineaPig => 60,
        PetSkin.fox => 80,
        PetSkin.ferret => 100,
        PetSkin.mochi => 120,
      };

  /// 是否為預設就擁有的外觀（狗狗）。其餘需購買 / 解鎖。
  bool get ownedByDefault => this == PetSkin.dog;

  /// 從存檔字串還原；認不得（含 null / 舊資料）一律回預設狗狗，永不 crash。
  static PetSkin fromStorageId(String? id) {
    return switch (id) {
      'guinea_pig' => PetSkin.guineaPig,
      'fox' => PetSkin.fox,
      'ferret' => PetSkin.ferret,
      'mochi' => PetSkin.mochi,
      _ => PetSkin.dog,
    };
  }
}
