class CareTask {
  const CareTask({
    required this.id,
    required this.title,
    required this.rewardCoins,
    required this.rewardBond,
    required this.completed,
  });

  final String id;
  final String title;
  final int rewardCoins;
  final int rewardBond;
  final bool completed;

  CareTask copyWith({bool? completed}) {
    return CareTask(
      id: id,
      title: title,
      rewardCoins: rewardCoins,
      rewardBond: rewardBond,
      completed: completed ?? this.completed,
    );
  }
}
