import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/models/user_profile.dart';
import 'package:pet_companion_app/services/local_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('LocalStorageService 依帳號隔離（CR-0009）', () {
    test('帳號 A 設「小白」、帳號 B 第一次 load 看不到、設「狐狸」、A 仍是「小白」',
        () async {
      final storage = LocalStorageService();

      // 帳號 A → 命名「小白」
      storage.setUserId('elder-A');
      await storage.saveProfile(
        UserProfile.initial().copyWith(
          petName: '小白',
          hasCompletedOnboarding: true,
        ),
      );

      // 帳號 B 第一次 → 全新（看不到「小白」、onboarding 未完成）
      storage.setUserId('elder-B');
      final bFirst = await storage.loadProfile();
      expect(bFirst.petName, isNot('小白'));
      expect(bFirst.hasCompletedOnboarding, false);

      // 帳號 B 設「狐狸」
      await storage.saveProfile(
        bFirst.copyWith(petName: '狐狸', hasCompletedOnboarding: true),
      );

      // 帳號 A 再 load → 仍是「小白」
      storage.setUserId('elder-A');
      final aAgain = await storage.loadProfile();
      expect(aAgain.petName, '小白');
      expect(aAgain.hasCompletedOnboarding, true);

      // 帳號 B → 仍是「狐狸」
      storage.setUserId('elder-B');
      expect((await storage.loadProfile()).petName, '狐狸');
    });

    test('default_user（Demo）沿用既有全域 key，不被真帳號污染', () async {
      // 模擬「升級前」已存在的全域 Demo 資料（無前綴 key）。
      SharedPreferences.setMockInitialValues({
        'petName': '小黑',
        'hasCompletedOnboarding': true,
      });
      final storage = LocalStorageService();

      // default_user（Demo / 未登入）→ 讀到既有全域資料。
      storage.setUserId('default_user');
      expect((await storage.loadProfile()).petName, '小黑');

      // 真帳號 → 看不到 Demo 的「小黑」。
      storage.setUserId('elder-A');
      expect((await storage.loadProfile()).petName, isNot('小黑'));

      // 真帳號寫入後，Demo 的全域資料不受影響。
      await storage.saveProfile(
        UserProfile.initial().copyWith(petName: '狐狸'),
      );
      storage.setUserId('default_user');
      expect((await storage.loadProfile()).petName, '小黑');
    });

    test('setUserId(空/null) 視為 default_user', () async {
      SharedPreferences.setMockInitialValues({'petName': '小黑'});
      final storage = LocalStorageService();
      storage.setUserId('');
      expect(storage.userId, 'default_user');
      expect((await storage.loadProfile()).petName, '小黑');
    });
  });
}
