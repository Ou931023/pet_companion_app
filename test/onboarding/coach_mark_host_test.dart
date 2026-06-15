import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pet_companion_app/controllers/app_navigation_controller.dart';
import 'package:pet_companion_app/onboarding/coach_mark_controller.dart';
import 'package:pet_companion_app/onboarding/coach_mark_keys.dart';
import 'package:pet_companion_app/onboarding/coach_mark_overlay.dart';
import 'package:pet_companion_app/services/local_storage_service.dart';

/// 可控制「是否已看過導覽」的假儲存，並記錄完成時是否寫回。
class _FakeStorage extends LocalStorageService {
  _FakeStorage(this._done);
  final bool _done;
  bool? savedDone;

  @override
  Future<bool> loadHomeCoachMarkDone() async => _done;

  @override
  Future<void> saveHomeCoachMarkDone(bool done) async {
    savedDone = done;
  }
}

Widget _app({
  required CoachMarkController controller,
  required CoachMarkKeys keys,
  required AppNavigationController nav,
  required LocalStorageService storage,
  required bool homeVisible,
  required Widget child,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<CoachMarkController>.value(value: controller),
      Provider<CoachMarkKeys>.value(value: keys),
      ChangeNotifierProvider<AppNavigationController>.value(value: nav),
      Provider<LocalStorageService>.value(value: storage),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: CoachMarkHost(homeVisible: homeVisible, child: child),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('首次進首頁（未看過 + petKey 就緒）會自動開始 16 步導覽', (tester) async {
    final controller = CoachMarkController();
    final keys = CoachMarkKeys();
    final nav = AppNavigationController();
    final storage = _FakeStorage(false);

    await tester.pumpWidget(_app(
      controller: controller,
      keys: keys,
      nav: nav,
      storage: storage,
      homeVisible: true,
      // 掛上 petKey，讓 host 判定首頁已繪製、可以開始。
      child: KeyedSubtree(key: keys.petKey, child: const SizedBox(width: 100, height: 100)),
    ));
    await tester.pump(); // postFrame 自動開始
    await tester.pump();

    expect(controller.isActive, isTrue);
    expect(controller.stepCount, 16);
    expect(find.text('第 1 步 / 共 16 步'), findsOneWidget);
  });

  testWidgets('已看過則不自動開始導覽', (tester) async {
    final controller = CoachMarkController();
    final keys = CoachMarkKeys();
    final nav = AppNavigationController();
    final storage = _FakeStorage(true);

    await tester.pumpWidget(_app(
      controller: controller,
      keys: keys,
      nav: nav,
      storage: storage,
      homeVisible: true,
      child: KeyedSubtree(key: keys.petKey, child: const SizedBox(width: 100, height: 100)),
    ));
    await tester.pump();
    await tester.pump();

    expect(controller.isActive, isFalse);
  });

  testWidgets(
      'CR-0092 跨頁：host 依步驟把分頁切到 商城(1)/紀錄(2)/設定(3)，最後回首頁(0) 並記錄已看過',
      (tester) async {
    final controller = CoachMarkController();
    final keys = CoachMarkKeys();
    final nav = AppNavigationController()..selectShellIndex(0);
    final storage = _FakeStorage(true); // 跳過自動開始，改手動 start 精準控制

    await tester.pumpWidget(_app(
      controller: controller,
      keys: keys,
      nav: nav,
      storage: storage,
      homeVisible: true,
      child: const SizedBox(),
    ));
    await tester.pump();

    final steps = buildHomeCoachMarkSteps(keys);
    controller.start(steps);
    await tester.pump();
    expect(nav.currentShellIndex, 0, reason: '首頁段(前 9 步)不切頁');

    // 前進到指定 step index，逐步驅動 host 的切頁。
    Future<void> advanceTo(int index) async {
      while (controller.currentIndex < index) {
        controller.markTypingDone();
        controller.next();
        await tester.pump();
      }
    }

    await advanceTo(9); // 商城
    expect(nav.currentShellIndex, 1, reason: 'Step 10 跨頁到商城分頁');
    await advanceTo(10); // 紀錄
    expect(nav.currentShellIndex, 2, reason: 'Step 11 跨頁到紀錄分頁');
    await advanceTo(12); // 設定（換造型）
    expect(nav.currentShellIndex, 3, reason: 'Step 13 跨頁到設定分頁');
    await advanceTo(steps.length - 1); // 最後一步：回首頁
    expect(nav.currentShellIndex, 0, reason: '最後一步切回首頁');

    // 完成導覽。
    controller.markTypingDone();
    controller.next();
    await tester.pump();
    expect(controller.isActive, isFalse);
    expect(nav.currentShellIndex, 0, reason: '完成後留在首頁');
    expect(storage.savedDone, isTrue, reason: '完成後記錄已看過，下次不自動顯示');
  });
}
