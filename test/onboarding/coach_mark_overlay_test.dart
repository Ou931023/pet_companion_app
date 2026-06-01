import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/onboarding/coach_mark_controller.dart';
import 'package:pet_companion_app/onboarding/coach_mark_keys.dart';
import 'package:pet_companion_app/onboarding/coach_mark_overlay.dart';

// targetKey 為 null → overlay 走「無高亮框、文字置中卡片」的降級路徑，
// 不依賴實際 widget 佈局，測試最穩定。
const _steps = [
  CoachMarkStep(text: '這是寵物'),
  CoachMarkStep(text: '這是設定'),
];

Widget _host(CoachMarkController controller, CoachMarkKeys keys) {
  return MaterialApp(
    home: Scaffold(
      body: Stack(
        children: [
          CoachMarkOverlay(controller: controller, keys: keys),
        ],
      ),
    ),
  );
}

/// 跑完逐字列印並 flush onCompleted 的 postFrame，讓「下一步」可被觸發。
Future<void> _finishTyping(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 2));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('提示卡顯示步數，右下角有小三角（非最後一步）', (tester) async {
    final controller = CoachMarkController()..start(_steps);
    await tester.pumpWidget(_host(controller, CoachMarkKeys()));
    await tester.pump();

    expect(find.text('第 1 步 / 共 2 步'), findsOneWidget);
    await _finishTyping(tester);
    // 小三角（非最後一步），且沒有舊版的「下一個」整排按鈕。
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.text('下一個'), findsNothing);
  });

  testWidgets('列印中點一下 → 先補完整文字、不前進；再點一下才進下一步', (tester) async {
    final controller = CoachMarkController()..start(_steps);
    await tester.pumpWidget(_host(controller, CoachMarkKeys()));
    await tester.pump();
    expect(controller.isTyping, isTrue);

    // 第一次點（畫面左上空白處 = 遮罩）：補完整文字，停在第 1 步。
    await tester.tapAt(const Offset(8, 8));
    await tester.pump();
    await tester.pump();
    expect(controller.isTyping, isFalse, reason: '第一次點先補完文字');
    expect(controller.currentIndex, 0, reason: '補完文字當下不前進');
    expect(find.text('第 1 步 / 共 2 步'), findsOneWidget);

    // 第二次點：進到第 2 步。
    await tester.tapAt(const Offset(8, 8));
    await tester.pump();
    expect(controller.currentIndex, 1);
    expect(find.text('第 2 步 / 共 2 步'), findsOneWidget);
  });

  testWidgets('點小三角可以進到下一步', (tester) async {
    final controller = CoachMarkController()..start(_steps);
    await tester.pumpWidget(_host(controller, CoachMarkKeys()));
    await _finishTyping(tester);

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(controller.currentIndex, 1);
  });

  testWidgets('最後一步顯示「開始使用」，點了結束導覽、overlay 消失', (tester) async {
    final controller = CoachMarkController()..start(_steps);
    await tester.pumpWidget(_host(controller, CoachMarkKeys()));
    await _finishTyping(tester);
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    await _finishTyping(tester);

    expect(find.text('開始使用'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);

    await tester.tap(find.text('開始使用'));
    await tester.pump();
    expect(controller.isActive, isFalse);
    expect(find.text('開始使用'), findsNothing);
  });

  testWidgets('沒有 target 的步驟 → 置中卡片，提示卡預設在上半部，不 crash', (tester) async {
    final controller = CoachMarkController()..start(_steps);
    await tester.pumpWidget(_host(controller, CoachMarkKeys()));
    await tester.pump();

    expect(tester.takeException(), isNull);
    // 預設上方提示卡：步數文字落在畫面上半部。
    final counter = tester.getRect(find.text('第 1 步 / 共 2 步'));
    final screenH = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(counter.center.dy, lessThan(screenH / 2));
  });

  testWidgets('小螢幕 + 長文字：導覽卡片不溢出', (tester) async {
    addTearDown(tester.view.reset);
    // 小螢幕 iPhone（約 320x568）。
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;

    final longSteps = [
      const CoachMarkStep(
        text: '這是你的 AI 寵物，牠會陪你聊天，也會慢慢記得你喜歡什麼，'
            '想說話、想設提醒、想說說今天的心情，都可以直接跟牠講，不用打字，'
            '想一起玩的時候輕輕點牠就能開始，慢慢來、不用著急。',
      ),
      const CoachMarkStep(text: '最下面的「設定」可以調整帳號和導覽。'),
    ];
    final controller = CoachMarkController()..start(longSteps);

    await tester.pumpWidget(_host(controller, CoachMarkKeys()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    // 任何 RenderFlex overflow 都會讓 takeException 非 null。
    expect(tester.takeException(), isNull);
  });
}
