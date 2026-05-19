import '../models/shop_item.dart';

class ShopService {
  const ShopService();

  static const Map<String, List<String>> _aliases = {
    'cookie': ['餅乾', '小餅乾', '狗狗餅乾', '點心'],
    'rice_ball': ['飯糰', '飯團'],
    'warm_milk': ['牛奶', '溫牛奶', '熱牛奶'],
    'juice': ['果汁', '飲料'],
    'salmon_bowl': ['鮭魚', '魚肉', '鮭魚餐', '鮭魚碗'],
    'chicken_soup': ['雞湯', '暖雞湯', '雞肉湯'],
    'yarn_ball': ['毛線球', '玩具球'],
    'bell': ['鈴鐺', '小鈴鐺'],
    'soft_blanket': ['毯子', '小毯子', '柔軟毯子'],
    'pet_bed': ['床', '小床', '寵物床', '午睡床'],
    'grooming_brush': ['梳子', '毛刷', '梳毛', '寵物梳'],
    'bath_towel': ['毛巾', '浴巾', '洗澡毛巾'],
    'story_book': ['故事書', '繪本', '睡前故事'],
    'music_box': ['音樂盒', '小音樂盒', '音樂'],
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
        id: 'salmon_bowl',
        name: '鮭魚餐',
        emoji: '🐟',
        category: '食物',
        price: 65,
        fullnessDelta: 38,
        moodDelta: 8,
        intimacyDelta: 3,
      ),
      ShopItem(
        id: 'chicken_soup',
        name: '暖雞湯',
        emoji: '🍲',
        category: '食物',
        price: 70,
        fullnessDelta: 32,
        moodDelta: 14,
        intimacyDelta: 4,
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
        id: 'story_book',
        name: '睡前故事書',
        emoji: '📖',
        category: '陪伴',
        price: 60,
        moodDelta: 18,
        intimacyDelta: 7,
      ),
      ShopItem(
        id: 'music_box',
        name: '小音樂盒',
        emoji: '🎵',
        category: '陪伴',
        price: 90,
        moodDelta: 28,
        intimacyDelta: 9,
      ),
      ShopItem(
        id: 'soft_blanket',
        name: '柔軟毯子',
        emoji: '🧣',
        category: '休息',
        price: 75,
        fullnessDelta: 0,
        moodDelta: 22,
        intimacyDelta: 6,
      ),
      ShopItem(
        id: 'pet_bed',
        name: '午睡小床',
        emoji: '🛏️',
        category: '休息',
        price: 120,
        moodDelta: 35,
        intimacyDelta: 10,
      ),
      ShopItem(
        id: 'grooming_brush',
        name: '梳毛刷',
        emoji: '🪮',
        category: '照護',
        price: 55,
        moodDelta: 16,
        intimacyDelta: 8,
      ),
      ShopItem(
        id: 'bath_towel',
        name: '洗澡浴巾',
        emoji: '🧺',
        category: '照護',
        price: 45,
        moodDelta: 12,
        intimacyDelta: 5,
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
