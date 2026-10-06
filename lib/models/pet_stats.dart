enum PetLifeState {
  alive,
  @Deprecated('Companion interaction is no longer blocked by low stats.')
  dead,
}

class PetStats {
  const PetStats({
    required this.intimacy,
    required this.fullness,
    required this.moodValue,
    required this.lastOpenedDate,
  });

  final int intimacy;
  final int fullness;
  final int moodValue;
  final String? lastOpenedDate;

  /// 陪伴不以數值處罰使用者。既有資料即使親密度已降到 0，寵物仍會陪伴、
  /// 接受觸摸與對話；數值只用來呈現當下需要，不再代表「死亡」或鎖住功能。
  PetLifeState get lifeState => PetLifeState.alive;

  PetStats copyWith({
    int? intimacy,
    int? fullness,
    int? moodValue,
    String? lastOpenedDate,
  }) {
    return PetStats(
      intimacy: intimacy ?? this.intimacy,
      fullness: fullness ?? this.fullness,
      moodValue: moodValue ?? this.moodValue,
      lastOpenedDate: lastOpenedDate ?? this.lastOpenedDate,
    );
  }

  factory PetStats.initial() {
    return const PetStats(
      intimacy: 30,
      fullness: 50,
      moodValue: 60,
      lastOpenedDate: null,
    );
  }
}
