import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pet_companion_app/screens/puzzle_game_screen.dart';

void main() {
  testWidgets('遊戲標題為「回憶拼圖」、入口在小螢幕不 overflow / 不 crash',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: PuzzleGameScreen()));
    await tester.pump();

    expect(find.text('回憶拼圖'), findsOneWidget); // AppBar 標題
    expect(find.text('照片拼圖'), findsNothing); // 舊名稱不再出現
    expect(find.text('選一張照片，拼回屬於你的回憶。'), findsOneWidget);
    expect(find.text('從相簿選照片'), findsOneWidget);
    // 任何 RenderFlex overflow 都會讓 takeException 非 null。
    expect(tester.takeException(), isNull);
  });
}
