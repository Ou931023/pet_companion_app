import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/controllers/pet_controller.dart';
import 'package:pet_companion_app/models/pet_skin.dart';
import 'package:pet_companion_app/services/local_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PetController 外觀（CR-0011）', () {
    test('預設外觀為狗狗', () {
      final controller = PetController();
      expect(controller.currentSkin, PetSkin.dog);
    });

    test('沒有 storage 也不會 crash（changeSkin 仍切換）', () async {
      final controller = PetController();
      await controller.changeSkin(PetSkin.fox);
      expect(controller.currentSkin, PetSkin.fox);
    });

    test('changeSkin 會即時切換並保存，重新載入後仍是該外觀', () async {
      final storage = LocalStorageService();
      final controller = PetController(storageService: storage);

      var notified = 0;
      controller.addListener(() => notified++);

      await controller.changeSkin(PetSkin.guineaPig);
      expect(controller.currentSkin, PetSkin.guineaPig);
      expect(notified, greaterThan(0));

      // 新的 controller 用同一個 storage loadSkin → 拿到天竺鼠
      final reloaded = PetController(storageService: storage);
      await reloaded.loadSkin();
      expect(reloaded.currentSkin, PetSkin.guineaPig);

      await controller.changeSkin(PetSkin.fox);
      final reloaded2 = PetController(storageService: storage);
      await reloaded2.loadSkin();
      expect(reloaded2.currentSkin, PetSkin.fox);
    });

    test('loadSkin 依 elderId 載入各自的外觀', () async {
      final storage = LocalStorageService();
      final controller = PetController(storageService: storage);

      storage.setUserId('elder-A');
      await controller.changeSkin(PetSkin.fox);

      // 切到 elder-B → loadSkin 應回預設狗狗
      storage.setUserId('elder-B');
      await controller.loadSkin();
      expect(controller.currentSkin, PetSkin.dog);

      // 切回 elder-A → loadSkin 應回狐狸
      storage.setUserId('elder-A');
      await controller.loadSkin();
      expect(controller.currentSkin, PetSkin.fox);
    });

    test('changeSkin 切到相同外觀不重複保存/通知', () async {
      final controller = PetController();
      var notified = 0;
      controller.addListener(() => notified++);
      await controller.changeSkin(PetSkin.dog); // 已是 dog
      expect(notified, 0);
    });
  });
}
