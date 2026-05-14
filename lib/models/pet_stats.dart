enum PetLifeState {
  alive,
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

  PetLifeState get lifeState =>
      intimacy <= 0 ? PetLifeState.dead : PetLifeState.alive;

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
