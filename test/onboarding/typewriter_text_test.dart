import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/onboarding/typewriter_text.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('逐字列印：先顯示部分，最後顯示完整並回呼 onCompleted', (tester) async {
    var completed = false;
    await tester.pumpWidget(_host(TypewriterText(
      text: '你好嗎',
      charDuration: const Duration(milliseconds: 30),
      onCompleted: () => completed = true,
    )));

    // 剛開始還沒列印完。
    await tester.pump(const Duration(milliseconds: 30));
    expect(find.text('你好嗎'), findsNothing);
    expect(completed, isFalse);

    // 等列印完成。
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(); // 跑 onCompleted 的 postFrame
    expect(find.text('你好嗎'), findsOneWidget);
    expect(completed, isTrue);
  });

  testWidgets('列印中觸發 revealSignal → 立刻顯示完整並回呼 onCompleted', (tester) async {
    var completed = false;
    final reveal = ValueNotifier<int>(0);
    addTearDown(reveal.dispose);
    await tester.pumpWidget(_host(TypewriterText(
      text: '吃飽了嗎',
      charDuration: const Duration(milliseconds: 200),
      onCompleted: () => completed = true,
      revealSignal: reveal,
    )));

    await tester.pump(const Duration(milliseconds: 200)); // 才印一兩個字
    expect(find.text('吃飽了嗎'), findsNothing);

    // 外層 overlay 點任意處時會 bump 這個訊號，要求立刻補完整文字。
    reveal.value++;
    await tester.pump(); // 完整顯示
    await tester.pump(); // onCompleted postFrame
    expect(find.text('吃飽了嗎'), findsOneWidget);
    expect(completed, isTrue);
  });

  testWidgets('空字串視為已完成', (tester) async {
    var completed = false;
    await tester.pumpWidget(_host(TypewriterText(
      text: '',
      onCompleted: () => completed = true,
    )));
    await tester.pump();
    expect(completed, isTrue);
  });
}
