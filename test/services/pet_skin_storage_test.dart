import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/models/pet_skin.dart';
import 'package:pet_companion_app/models/pet_visual_profile.dart';
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

  group('已擁有外觀本機保存', () {
    test('沒存過 → 預設只擁有狗狗', () async {
      final storage = LocalStorageService();
      expect(await storage.loadOwnedPetSkins(), {PetSkin.dog});
    });

    test('保存後可讀回，且狗狗永遠保底在內', () async {
      final storage = LocalStorageService();
      await storage.saveOwnedPetSkins({PetSkin.fox});
      expect(await storage.loadOwnedPetSkins(), {PetSkin.dog, PetSkin.fox});

      await storage.saveOwnedPetSkins({PetSkin.guineaPig, PetSkin.fox});
      expect(
        await storage.loadOwnedPetSkins(),
        {PetSkin.dog, PetSkin.guineaPig, PetSkin.fox},
      );
    });

    test('不同 elderId 的已擁有外觀互不影響', () async {
      final storage = LocalStorageService();
      storage.setUserId('elder-A');
      await storage.saveOwnedPetSkins({PetSkin.fox});

      storage.setUserId('elder-B');
      expect(await storage.loadOwnedPetSkins(), {PetSkin.dog});

      storage.setUserId('elder-A');
      expect(await storage.loadOwnedPetSkins(), {PetSkin.dog, PetSkin.fox});
    });
  });

  group('寵物視覺風格預設 migration', () {
    test('真正新使用者預設 realistic，並一次性回填偏好', () async {
      final storage = LocalStorageService();

      expect(await storage.loadPetVisualStyle(), PetVisualStyle.realistic);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('petVisualStyle'), 'realistic');

      await storage.savePetSkin(PetSkin.dog);
      expect(await storage.loadPetVisualStyle(), PetVisualStyle.realistic);
    });

    test('升級前已有寵物資料但沒有 visual style 時保留 cute', () async {
      SharedPreferences.setMockInitialValues({
        'petSkin': 'fox',
        'ownedPetSkins': <String>['dog', 'fox'],
      });
      final storage = LocalStorageService();

      expect(await storage.loadPetVisualStyle(), PetVisualStyle.cute);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('petVisualStyle'), 'cute');
    });

    test('升級前已有其他舊資料時保留 cute', () async {
      SharedPreferences.setMockInitialValues({'petName': '小福'});
      final storage = LocalStorageService();

      expect(await storage.loadPetVisualStyle(), PetVisualStyle.cute);
    });

    test('migration 依 elderId 隔離，舊帳號不影響真正新帳號', () async {
      SharedPreferences.setMockInitialValues({
        'u:elder-A:petSkin': 'fox',
      });
      final storage = LocalStorageService();

      storage.setUserId('elder-A');
      expect(await storage.loadPetVisualStyle(), PetVisualStyle.cute);

      storage.setUserId('elder-B');
      expect(await storage.loadPetVisualStyle(), PetVisualStyle.realistic);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('u:elder-A:petVisualStyle'), 'cute');
      expect(prefs.getString('u:elder-B:petVisualStyle'), 'realistic');
    });

    test('既有顯式 cute / realistic 偏好都完整保留', () async {
      SharedPreferences.setMockInitialValues({
        'u:elder-A:petVisualStyle': 'cute',
        'u:elder-B:petVisualStyle': 'realistic',
      });
      final storage = LocalStorageService();

      storage.setUserId('elder-A');
      expect(await storage.loadPetVisualStyle(), PetVisualStyle.cute);

      storage.setUserId('elder-B');
      expect(await storage.loadPetVisualStyle(), PetVisualStyle.realistic);
    });
  });
}
