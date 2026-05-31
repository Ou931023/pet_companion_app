import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/models/pet_stats.dart';
import 'package:pet_companion_app/services/pet_stats_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('PetStats 依帳號隔離（CR-0009）：A/B 各自獨立、Demo 沿用全域', () async {
    final storage = PetStatsStorageService();

    storage.setUserId('elder-A');
    await storage.save(PetStats.initial().copyWith(intimacy: 88));

    // 帳號 B 第一次 → 預設值，不是 A 的 88。
    storage.setUserId('elder-B');
    final b = await storage.load();
    expect(b.intimacy, isNot(88));

    // A 仍是 88。
    storage.setUserId('elder-A');
    expect((await storage.load()).intimacy, 88);
  });
}
