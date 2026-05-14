import '../models/shop_item.dart';

class ShopService {
  const ShopService();

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
}
