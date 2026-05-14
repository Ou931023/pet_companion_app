class ShopItem {
  const ShopItem({
    required this.id,
    required this.name,
    required this.emoji,
    required this.category,
    required this.price,
    this.intimacyDelta = 0,
    this.fullnessDelta = 0,
    this.moodDelta = 0,
    this.onlyWhenDead = false,
    this.isRevive = false,
  });

  final String id;
  final String name;
  final String emoji;
  final String category;
  final int price;
  final int intimacyDelta;
  final int fullnessDelta;
  final int moodDelta;
  final bool onlyWhenDead;
  final bool isRevive;
}
