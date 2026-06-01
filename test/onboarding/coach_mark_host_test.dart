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

  testWidgets('首次進首頁（未看過 + petKey 就緒）會自動開始 13 步導覽', (tester) async {
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
    expect(controller.stepCount, 13);
    expect(find.text('第 1 步 / 共 13 步'), findsOneWidget);
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

  testWidgets('Step 13 跨頁：host 把底部分頁切到設定(index 3)；完成後切回首頁(0) 並記錄已看過',
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

    controller.start(buildHomeCoachMarkSteps(keys));
    await tester.pump();
    expect(nav.currentShellIndex, 0, reason: '前 12 步都在首頁，不切頁');

    // 前進到最後一步（共 13 步 → next 12 次）。
    for (var i = 0; i < 12; i++) {
      controller.markTypingDone();
      controller.next();
      await tester.pump();
    }
    expect(controller.currentIndex, 12, reason: '已到第 13 步');
    expect(nav.currentShellIndex, 3, reason: 'Step 13 應跨頁切到設定分頁');

    // 完成導覽。
    controller.markTypingDone();
    controller.next();
    await tester.pump();
    expect(controller.isActive, isFalse);
    expect(nav.currentShellIndex, 0, reason: '完成後切回首頁，不把使用者留在設定頁');
    expect(storage.savedDone, isTrue, reason: '完成後記錄已看過，下次不自動顯示');
  });
}
