import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/controllers/pet_controller.dart';
import 'package:pet_companion_app/models/pet_skin.dart';
import 'package:pet_companion_app/services/local_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PetController 外觀擁有 / 套用 / 購買（CR-0011 + 解鎖）', () {
    test('預設外觀為狗狗，且預設只擁有狗狗', () {
      final controller = PetController();
      expect(controller.currentSkin, PetSkin.dog);
      expect(controller.isOwned(PetSkin.dog), isTrue);
      expect(controller.isOwned(PetSkin.guineaPig), isFalse);
      expect(controller.isOwned(PetSkin.fox), isFalse);
      expect(controller.ownedSkins, {PetSkin.dog});
    });

    test('外觀清單包含 dog / guineaPig / fox', () {
      expect(PetSkin.values, containsAll(<PetSkin>[
        PetSkin.dog,
        PetSkin.guineaPig,
        PetSkin.fox,
      ]));
    });

    test('已擁有的外觀可以套用（dog）', () async {
      final controller = PetController();
      // 先免費取得 fox 當起始夥伴 → 已擁有 → 可在 dog / fox 間切換。
      await controller.selectStarterSkin(PetSkin.fox);
      final ok = await controller.changeSkin(PetSkin.dog);
      expect(ok, isTrue);
      expect(controller.currentSkin, PetSkin.dog);
    });

    test('未擁有的外觀不能直接套用：changeSkin 回 false、維持原外觀', () async {
      final controller = PetController();
      final ok = await controller.changeSkin(PetSkin.fox);
      expect(ok, isFalse);
      expect(controller.currentSkin, PetSkin.dog);
      expect(controller.isOwned(PetSkin.fox), isFalse);
    });

    test('selectStarterSkin：免費解鎖並套用（新手導覽選夥伴）', () async {
      final controller = PetController();
      await controller.selectStarterSkin(PetSkin.guineaPig);
      expect(controller.currentSkin, PetSkin.guineaPig);
      expect(controller.isOwned(PetSkin.guineaPig), isTrue);
    });

    test('purchaseAndApplySkin：點數足夠 → 扣點、解鎖、套用', () async {
      final controller = PetController();
      int? charged;
      final result = await controller.purchaseAndApplySkin(
        PetSkin.fox,
        spendCoins: (cost) async {
          charged = cost;
          return true; // 點數足夠
        },
      );
      expect(result, SkinPurchaseResult.purchasedAndApplied);
      expect(charged, PetSkin.fox.unlockCost);
      expect(controller.isOwned(PetSkin.fox), isTrue);
      expect(controller.currentSkin, PetSkin.fox);
    });

    test('purchaseAndApplySkin：點數不足 → 不扣點、不解鎖、維持原外觀', () async {
      final controller = PetController();
      final result = await controller.purchaseAndApplySkin(
        PetSkin.fox,
        spendCoins: (_) async => false, // 點數不足
      );
      expect(result, SkinPurchaseResult.insufficientCoins);
      expect(controller.isOwned(PetSkin.fox), isFalse);
      expect(controller.currentSkin, PetSkin.dog);
    });

    test('purchaseAndApplySkin：已擁有 → 直接套用、不再扣點', () async {
      final controller = PetController();
      await controller.selectStarterSkin(PetSkin.fox);
      await controller.changeSkin(PetSkin.dog);
      var spendCalled = false;
      final result = await controller.purchaseAndApplySkin(
        PetSkin.fox,
        spendCoins: (_) async {
          spendCalled = true;
          return true;
        },
      );
      expect(result, SkinPurchaseResult.applied);
      expect(spendCalled, isFalse);
      expect(controller.currentSkin, PetSkin.fox);
    });

    test('套用 / 解鎖後持久化：重新載入仍保留已擁有與目前外觀', () async {
      final storage = LocalStorageService();
      final controller = PetController(storageService: storage);
      await controller.purchaseAndApplySkin(
        PetSkin.guineaPig,
        spendCoins: (_) async => true,
      );
      expect(controller.currentSkin, PetSkin.guineaPig);

      final reloaded = PetController(storageService: storage);
      await reloaded.loadSkin();
      expect(reloaded.currentSkin, PetSkin.guineaPig);
      expect(reloaded.isOwned(PetSkin.guineaPig), isTrue);
      expect(reloaded.isOwned(PetSkin.dog), isTrue);
    });

    test('loadSkin 依 elderId 載入各自的外觀與擁有狀態', () async {
      final storage = LocalStorageService();
      final controller = PetController(storageService: storage);

      storage.setUserId('elder-A');
      await controller.selectStarterSkin(PetSkin.fox);

      // elder-B：沒解鎖過 → 只有狗狗、目前狗狗。
      storage.setUserId('elder-B');
      await controller.loadSkin();
      expect(controller.currentSkin, PetSkin.dog);
      expect(controller.isOwned(PetSkin.fox), isFalse);

      // 切回 elder-A → 仍擁有並使用狐狸。
      storage.setUserId('elder-A');
      await controller.loadSkin();
      expect(controller.currentSkin, PetSkin.fox);
      expect(controller.isOwned(PetSkin.fox), isTrue);
    });

    test('防呆：存到的目前外觀不在已擁有清單 → 退回狗狗', () async {
      final storage = LocalStorageService();
      // 直接寫入「目前外觀=fox」但沒有解鎖紀錄（模擬異常資料）。
      await storage.savePetSkin(PetSkin.fox);
      final controller = PetController(storageService: storage);
      await controller.loadSkin();
      expect(controller.currentSkin, PetSkin.dog);
    });

    test('changeSkin 切到相同且已擁有的外觀 → 不重複通知', () async {
      final controller = PetController();
      var notified = 0;
      controller.addListener(() => notified++);
      final ok = await controller.changeSkin(PetSkin.dog); // 已是 dog
      expect(ok, isTrue);
      expect(notified, 0);
    });
  });
}
