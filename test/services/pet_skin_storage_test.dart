import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/models/pet_skin.dart';
import 'package:pet_companion_app/services/local_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('寵物外觀本機保存（CR-0011）', () {
    test('沒存過 → 預設狗狗', () async {
      final storage = LocalStorageService();
      expect(await storage.loadPetSkin(), PetSkin.dog);
    });

    test('保存後可讀回（狗狗 / 天竺鼠 / 狐狸）', () async {
      final storage = LocalStorageService();
      await storage.savePetSkin(PetSkin.guineaPig);
      expect(await storage.loadPetSkin(), PetSkin.guineaPig);
      await storage.savePetSkin(PetSkin.fox);
      expect(await storage.loadPetSkin(), PetSkin.fox);
    });

    test('不同 elderId 的外觀互不影響', () async {
      final storage = LocalStorageService();

      storage.setUserId('elder-A');
      await storage.savePetSkin(PetSkin.fox);

      // elder-B 第一次 → 看不到 A 的狐狸，回預設狗狗
      storage.setUserId('elder-B');
      expect(await storage.loadPetSkin(), PetSkin.dog);
      await storage.savePetSkin(PetSkin.guineaPig);

      // A 仍是狐狸、B 仍是天竺鼠
      storage.setUserId('elder-A');
      expect(await storage.loadPetSkin(), PetSkin.fox);
      storage.setUserId('elder-B');
      expect(await storage.loadPetSkin(), PetSkin.guineaPig);
    });

    test('default_user（Demo）用全域 key，不被真帳號污染', () async {
      final storage = LocalStorageService();

      storage.setUserId('default_user');
      await storage.savePetSkin(PetSkin.fox);

      storage.setUserId('elder-A');
      expect(await storage.loadPetSkin(), PetSkin.dog); // 真帳號看不到 Demo 的狐狸
      await storage.savePetSkin(PetSkin.guineaPig);

      storage.setUserId('default_user');
      expect(await storage.loadPetSkin(), PetSkin.fox); // Demo 不受影響
    });
  });
}
