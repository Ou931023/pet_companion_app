import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/models/user_profile.dart';
import 'package:pet_companion_app/services/local_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// CR-0087：寵物關心提醒的本機持久化 —— 設定開關 + cooldown 紀錄，且依帳號隔離。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('concernRemindersEnabled 預設開啟，可關閉並存回', () async {
    final storage = LocalStorageService();
    final initial = await storage.loadProfile();
    expect(initial.concernRemindersEnabled, isTrue);

    await storage.saveProfile(
      UserProfile.initial().copyWith(concernRemindersEnabled: false),
    );
    final reloaded = await storage.loadProfile();
    expect(reloaded.concernRemindersEnabled, isFalse);
  });

  test('cooldown 紀錄：沒存過 → 空 map；存後可讀回', () async {
    final storage = LocalStorageService();
    expect(await storage.loadConcernNotifyTimestamps(), isEmpty);

    await storage.saveConcernNotifyTimestamps({
      'low_mood_care': '2026-06-15T20:00:00.000',
      '_any': '2026-06-15T20:00:00.000',
    });
    final loaded = await storage.loadConcernNotifyTimestamps();
    expect(loaded['low_mood_care'], '2026-06-15T20:00:00.000');
    expect(loaded['_any'], '2026-06-15T20:00:00.000');
  });

  test('cooldown 紀錄依帳號隔離（A 的紀錄不會污染 B）', () async {
    final storage = LocalStorageService();
    storage.setUserId('elder-A');
    await storage.saveConcernNotifyTimestamps({'_any': '2026-06-15T20:00:00.000'});

    storage.setUserId('elder-B');
    expect(await storage.loadConcernNotifyTimestamps(), isEmpty);

    storage.setUserId('elder-A');
    final back = await storage.loadConcernNotifyTimestamps();
    expect(back['_any'], '2026-06-15T20:00:00.000');
  });
}
