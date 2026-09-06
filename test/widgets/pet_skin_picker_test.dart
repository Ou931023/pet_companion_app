import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pet_companion_app/controllers/pet_controller.dart';
import 'package:pet_companion_app/controllers/profile_controller.dart';
import 'package:pet_companion_app/controllers/wallet_controller.dart';
import 'package:pet_companion_app/models/pet_skin.dart';
import 'package:pet_companion_app/models/pet_visual_profile.dart';
import 'package:pet_companion_app/services/local_storage_service.dart';
import 'package:pet_companion_app/widgets/pet_skin_picker.dart';

/// 可控點數的假錢包（覆寫 coins / spendCoins，不碰真實 profile / 儲存）。
class _FakeWallet extends WalletController {
  _FakeWallet(this._coins) : super(ProfileController(LocalStorageService()));

  int _coins;

  @override
  int get coins => _coins;

  @override
  Future<bool> spendCoins(int amount) async {
    if (_coins < amount) return false;
    _coins -= amount;
    notifyListeners();
    return true;
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required PetController pet,
  required WalletController wallet,
  bool purchasable = true,
  ValueChanged<PetSkin>? onSkinApplied,
}) {
  return tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<PetController>.value(value: pet),
        ChangeNotifierProvider<WalletController>.value(value: wallet),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PetSkinPicker(
              purchasable: purchasable,
              onSkinApplied: onSkinApplied,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('已擁有的狗狗標「使用中」，未擁有的顯示解鎖點數', (tester) async {
    await _pump(tester, pet: PetController(), wallet: _FakeWallet(0));

    expect(find.text('狗狗'), findsOneWidget);
    expect(find.text('天竺鼠'), findsOneWidget);
    expect(find.text('狐狸'), findsOneWidget);
    expect(find.text('使用中'), findsOneWidget); // 只有目前的 dog
    expect(find.text('解鎖 ${PetSkin.guineaPig.unlockCost}'), findsOneWidget);
    expect(find.text('解鎖 ${PetSkin.fox.unlockCost}'), findsOneWidget);
  });

  testWidgets('點未擁有的外觀 → 先出現確認視窗（不直接扣點）', (tester) async {
    final pet = PetController();
    await _pump(tester, pet: pet, wallet: _FakeWallet(100));

    await tester.tap(find.text('狐狸'));
    await tester.pumpAndSettle();

    // 出現確認視窗，且尚未套用 / 扣點。
    expect(find.text('解鎖狐狸'), findsOneWidget);
    expect(
        find.text('要用 ${PetSkin.fox.unlockCost} 點解鎖狐狸，並換上牠嗎？'), findsOneWidget);
    expect(pet.currentSkin, PetSkin.dog);
    expect(pet.isOwned(PetSkin.fox), isFalse);
  });

  testWidgets('確認解鎖 + 點數足夠 → 套用狐狸並提示', (tester) async {
    final pet = PetController();
    await _pump(tester, pet: pet, wallet: _FakeWallet(100));

    await tester.tap(find.text('狐狸'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '解鎖'));
    await tester.pumpAndSettle();

    expect(pet.currentSkin, PetSkin.fox);
    expect(pet.isOwned(PetSkin.fox), isTrue);
    expect(find.textContaining('已經幫你換上狐狸'), findsOneWidget);
  });

  testWidgets('成功換上外觀後才觸發 onSkinApplied，重複點使用中不觸發', (tester) async {
    final pet = PetController();
    final selected = <PetSkin>[];
    await _pump(
      tester,
      pet: pet,
      wallet: _FakeWallet(100),
      onSkinApplied: selected.add,
    );

    await tester.tap(find.text('狗狗'));
    await tester.pumpAndSettle();
    expect(selected, isEmpty);

    await tester.tap(find.text('狐狸'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '解鎖'));
    await tester.pumpAndSettle();

    expect(selected, [PetSkin.fox]);
  });

  testWidgets('狗狗顯示 Q版 / 真實版選項，切換真實版會觸發追蹤 callback', (tester) async {
    final pet = PetController();
    await pet.changeVisualStyle(PetVisualStyle.cute);
    final selected = <PetSkin>[];
    await _pump(
      tester,
      pet: pet,
      wallet: _FakeWallet(0),
      onSkinApplied: selected.add,
    );

    expect(find.text('狗狗樣子'), findsOneWidget);
    expect(find.text('Q版'), findsOneWidget);
    expect(find.text('真實版'), findsOneWidget);
    expect(find.text('推薦'), findsOneWidget);

    await tester.tap(find.text('真實版'));
    await tester.pumpAndSettle();

    expect(selected, [PetSkin.dog]);
    expect(find.text('已換成真實版狗狗。'), findsOneWidget);
  });

  testWidgets('非狗狗不顯示真實版入口，避免正式版出現未完成選項', (tester) async {
    final pet = PetController(freeAllSkins: true);
    await _pump(tester, pet: pet, wallet: _FakeWallet(0));

    await tester.tap(find.text('狐狸'));
    await tester.pumpAndSettle();

    expect(pet.currentSkin, PetSkin.fox);
    expect(find.text('狗狗樣子'), findsNothing);
    expect(find.text('真實版'), findsNothing);
  });

  testWidgets('點數不足 → 白話提醒、不扣點、不解鎖', (tester) async {
    final pet = PetController();
    await _pump(tester, pet: pet, wallet: _FakeWallet(10));

    await tester.tap(find.text('狐狸'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '解鎖'));
    await tester.pumpAndSettle();

    expect(find.text('點數還不夠喔，可以先完成每日任務再來解鎖。'), findsOneWidget);
    expect(pet.currentSkin, PetSkin.dog);
    expect(pet.isOwned(PetSkin.fox), isFalse);
  });

  testWidgets('新手導覽模式（purchasable:false）→ 免費直接挑起始夥伴、無確認視窗', (tester) async {
    final pet = PetController();
    await _pump(
      tester,
      pet: pet,
      wallet: _FakeWallet(0),
      purchasable: false,
    );

    await tester.tap(find.text('狐狸'));
    await tester.pumpAndSettle();

    expect(find.text('解鎖狐狸'), findsNothing); // 沒有購買確認
    expect(pet.currentSkin, PetSkin.fox);
    expect(pet.isOwned(PetSkin.fox), isTrue);
  });
}
