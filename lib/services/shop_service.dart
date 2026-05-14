import '../models/shop_item.dart';

class ShopService {
  const ShopService();

  static const Map<String, List<String>> _aliases = {
    'cookie': ['餅乾', '小餅乾', '狗狗餅乾', '點心'],
    'rice_ball': ['飯糰', '飯團'],
    'warm_milk': ['牛奶', '溫牛奶', '熱牛奶'],
    'juice': ['果汁', '飲料'],
    'yarn_ball': ['毛線球', '玩具球'],
    'bell': ['鈴鐺', '小鈴鐺'],
    'revive_potion': ['復活', '復活藥水', '藥水'],
  };

  List<ShopItem> allItems() {
    return const [
      ShopItem(
        id: 'cookie',
        name: '小餅乾',
        emoji: '🍪',
        category: '食物',
        price: 20,
        fullnessDelta: 15,
        moodDelta: 3,
        intimacyDelta: 1,
      ),
      ShopItem(
        id: 'rice_ball',
        name: '飯糰',
        emoji: '🍙',
        category: '食物',
        price: 40,
        fullnessDelta: 30,
        moodDelta: 5,
        intimacyDelta: 2,
      ),
      ShopItem(
        id: 'warm_milk',
        name: '溫牛奶',
        emoji: '🥛',
        category: '飲料',
        price: 30,
        fullnessDelta: 10,
        moodDelta: 8,
        intimacyDelta: 2,
      ),
      ShopItem(
        id: 'juice',
        name: '果汁',
        emoji: '🧃',
        category: '飲料',
        price: 35,
        fullnessDelta: 8,
        moodDelta: 12,
        intimacyDelta: 1,
      ),
      ShopItem(
        id: 'yarn_ball',
        name: '毛線球',
        emoji: '🧶',
        category: '玩具',
        price: 50,
        moodDelta: 20,
        intimacyDelta: 5,
      ),
      ShopItem(
        id: 'bell',
        name: '小鈴鐺',
        emoji: '🔔',
        category: '玩具',
        price: 80,
        moodDelta: 25,
        intimacyDelta: 8,
      ),
      ShopItem(
        id: 'revive_potion',
        name: '復活藥水',
        emoji: '🧪',
        category: '特殊',
        price: 150,
        onlyWhenDead: true,
        isRevive: true,
      ),
    ];
  }

  ShopItem? findByText(String text) {
    final normalized = text.trim();
    for (final item in allItems()) {
      if (normalized.contains(item.name)) return item;
      final aliases = _aliases[item.id] ?? const [];
      if (aliases.any(normalized.contains)) return item;
    }
    return null;
  }
}
