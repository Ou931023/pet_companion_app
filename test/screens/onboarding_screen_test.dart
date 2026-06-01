import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pet_companion_app/controllers/pet_controller.dart';
import 'package:pet_companion_app/controllers/profile_controller.dart';
import 'package:pet_companion_app/screens/onboarding_screen.dart';
import 'package:pet_companion_app/services/local_storage_service.dart';

/// 不碰真實儲存，並記錄 saveHomeCoachMarkDone 是否被呼叫（驗證註冊完成後
/// 不會自動跳出首頁 coach mark）。
class _FakeStorage extends LocalStorageService {
  bool? savedCoachMarkDone;

  @override
  Future<void> saveHomeCoachMarkDone(bool done) async {
    savedCoachMarkDone = done;
  }
}

/// 不碰真實儲存的 ProfileController：記錄 completeOnboarding / setFamilyContacts
/// 被呼叫的內容，驗證多步驟設定 UI 有正確串到既有方法（邏輯本身未改）。
class _FakeProfileController extends ProfileController {
  _FakeProfileController(super.storage);

  String? completedName;
  List<Map<String, String>>? savedContacts;
  bool _onboarded = false;

  @override
  bool get hasCompletedOnboarding => _onboarded;

  @override
  Future<void> completeOnboarding(String petName) async {
    completedName = petName;
    _onboarded = true;
    notifyListeners();
  }

  @override
  Future<void> setFamilyContacts(List<Map<String, String>> contacts) async {
    savedContacts = contacts;
    notifyListeners();
  }
}

Future<void> _pumpOnboarding(
  WidgetTester tester, {
  required ProfileController profile,
  required LocalStorageService storage,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ProfileController>.value(value: profile),
        ChangeNotifierProvider<PetController>(create: (_) => PetController()),
        Provider<LocalStorageService>.value(value: storage),
      ],
      child: const MaterialApp(home: OnboardingScreen()),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void useTallView(WidgetTester tester) {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 1.0;
  }

  testWidgets('三步驟順序為 選夥伴 → 取名 → 設定關心你的人 → 完成註冊，且無重複的選外觀步驟',
      (tester) async {
    useTallView(tester);
    final storage = _FakeStorage();
    final profile = _FakeProfileController(storage);
    await _pumpOnboarding(tester, profile: profile, storage: storage);

    // 不再有舊版多頁導覽：註冊後直接進入設定步驟，畫面上沒有「略過」。
    expect(find.text('略過'), findsNothing);
    expect(find.text('歡迎使用愛陪伴'), findsNothing);

    // 第一步：選夥伴（同時是外觀）。
    expect(find.text('選一位陪伴你的夥伴'), findsOneWidget);
    expect(find.text('步驟 1 / 3'), findsOneWidget);
    // 不應再出現獨立的「選擇喜歡的外觀」步驟。
    expect(find.text('選擇喜歡的外觀'), findsNothing);

    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();

    // 第二步：取名字。
    expect(find.text('幫牠取一個名字'), findsOneWidget);
    expect(find.text('步驟 2 / 3'), findsOneWidget);
    expect(find.text('選擇喜歡的外觀'), findsNothing);

    await tester.enterText(find.byType(TextField).first, '小可愛');
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();

    // 第三步：設定關心你的人。
    expect(find.text('設定關心你的人'), findsOneWidget);
    expect(find.text('步驟 3 / 3'), findsOneWidget);

    await tester.tap(find.text('完成設定'));
    await tester.pumpAndSettle();

    // 完成儀式顯示實際名字，且命名前不可寫死「小白」。
    expect(find.text('完成註冊！'), findsOneWidget);
    expect(find.text('小可愛 準備好陪你開始生活了。'), findsOneWidget);
    expect(find.textContaining('小白'), findsNothing);

    // 按「開始使用」才真正呼叫既有 completeOnboarding。
    // 真實 App 此時 AuthGate 會換頁；測試中本頁仍在，故用 pump() flush。
    await tester.tap(find.text('開始使用'));
    await tester.pump();
    expect(profile.completedName, '小可愛');

    // 完成註冊後不會自動顯示舊 coach mark：已寫入「已看過」旗標。
    expect(storage.savedCoachMarkDone, isTrue);
  });

  testWidgets('第二步未取名按下一步 → 白話提醒、停在取名步驟、不呼叫 completeOnboarding',
      (tester) async {
    useTallView(tester);
    final storage = _FakeStorage();
    final profile = _FakeProfileController(storage);
    await _pumpOnboarding(tester, profile: profile, storage: storage);

    await tester.tap(find.text('下一步')); // 選夥伴 → 取名
    await tester.pumpAndSettle();

    await tester.tap(find.text('下一步')); // 取名步驟未填 → 應被擋下
    await tester.pump();

    expect(find.text('還沒有幫牠取名字唷'), findsOneWidget);
    expect(find.text('幫牠取一個名字'), findsOneWidget);
    expect(profile.completedName, isNull);
  });

  testWidgets('填了家人聯絡 → 透過既有 setFamilyContacts 保存', (tester) async {
    useTallView(tester);
    final storage = _FakeStorage();
    final profile = _FakeProfileController(storage);
    await _pumpOnboarding(tester, profile: profile, storage: storage);

    await tester.tap(find.text('下一步')); // 選夥伴 → 取名
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '球球');
    await tester.tap(find.text('下一步')); // 取名 → 設定關心你的人
    await tester.pumpAndSettle();

    // 設定關心你的人：alias / phone 兩個欄位。
    await tester.enterText(find.byType(TextField).at(0), '女兒');
    await tester.enterText(find.byType(TextField).at(1), '0912345678');
    await tester.tap(find.text('完成設定'));
    await tester.pumpAndSettle();

    expect(profile.savedContacts, isNotNull);
    expect(profile.savedContacts!.first['alias'], '女兒');
    expect(profile.savedContacts!.first['phone'], '0912345678');
  });
}
