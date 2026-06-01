import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/onboarding/coach_mark_controller.dart';
import 'package:pet_companion_app/onboarding/coach_mark_keys.dart';
import 'package:pet_companion_app/onboarding/coach_mark_overlay.dart';

// targetKey 為 null → overlay 走「無高亮框、文字置中」的降級路徑，
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

FilledButton _button(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byType(FilledButton));

Future<void> _finishTyping(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 2)); // 跑完逐字列印
  await tester.pump(); // onCompleted 的 postFrame → markTypingDone
  await tester.pump(); // 重建 → 按鈕解鎖
}

void main() {
  testWidgets('列印未完成時「下一個」鎖住，完成後解鎖', (tester) async {
    final controller = CoachMarkController()..start(_steps);
    await tester.pumpWidget(_host(controller, CoachMarkKeys()));

    await tester.pump();
    expect(find.text('第 1 步 / 共 2 步'), findsOneWidget);
    expect(_button(tester).onPressed, isNull, reason: '列印中應鎖住');

    await _finishTyping(tester);
    expect(controller.isTyping, isFalse);
    expect(_button(tester).onPressed, isNotNull, reason: '列印完成應解鎖');
    expect(find.text('下一個'), findsOneWidget);
  });

  testWidgets('點下一個 → 前進到第二步（最後一步顯示開始使用）', (tester) async {
    final controller = CoachMarkController()..start(_steps);
    await tester.pumpWidget(_host(controller, CoachMarkKeys()));

    await _finishTyping(tester);
    await tester.tap(find.text('下一個'));
    await tester.pump();

    expect(controller.currentIndex, 1);
    expect(find.text('第 2 步 / 共 2 步'), findsOneWidget);
    expect(controller.isTyping, isTrue, reason: '新步驟重新列印');

    await _finishTyping(tester);
    expect(find.text('開始使用'), findsOneWidget);
  });

  testWidgets('最後一步按開始使用 → 結束導覽、overlay 消失', (tester) async {
    final controller = CoachMarkController()..start(_steps);
    await tester.pumpWidget(_host(controller, CoachMarkKeys()));

    await _finishTyping(tester);
    await tester.tap(find.text('下一個'));
    await tester.pump();
    await _finishTyping(tester);

    await tester.tap(find.text('開始使用'));
    await tester.pump();

    expect(controller.isActive, isFalse);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('開始使用'), findsNothing);
  });
}
