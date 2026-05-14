class InventoryItem {
  const InventoryItem({
    required this.itemId,
    required this.name,
    required this.emoji,
    required this.quantity,
    required this.category,
    required this.intimacyDelta,
    required this.fullnessDelta,
    required this.moodDelta,
    required this.isReviveItem,
  });

  final String itemId;
  final String name;
  final String emoji;
  final int quantity;
  final String category;
  final int intimacyDelta;
  final int fullnessDelta;
  final int moodDelta;
  final bool isReviveItem;

  InventoryItem copyWith({
    int? quantity,
  }) {
    return InventoryItem(
      itemId: itemId,
      name: name,
      emoji: emoji,
      quantity: quantity ?? this.quantity,
      category: category,
      intimacyDelta: intimacyDelta,
      fullnessDelta: fullnessDelta,
      moodDelta: moodDelta,
      isReviveItem: isReviveItem,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'itemId': itemId,
      'name': name,
      'emoji': emoji,
      'quantity': quantity,
      'category': category,
      'intimacyDelta': intimacyDelta,
      'fullnessDelta': fullnessDelta,
      'moodDelta': moodDelta,
      'isReviveItem': isReviveItem,
    };
  }

  factory InventoryItem.fromJson(Map<String, dynamic> json) {
    return InventoryItem(
      itemId: json['itemId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      emoji: json['emoji'] as String? ?? '🎁',
      quantity: json['quantity'] as int? ?? 0,
      category: json['category'] as String? ?? '',
      intimacyDelta: json['intimacyDelta'] as int? ?? 0,
      fullnessDelta: json['fullnessDelta'] as int? ?? 0,
      moodDelta: json['moodDelta'] as int? ?? 0,
      isReviveItem: json['isReviveItem'] as bool? ?? false,
    );
  }
}
