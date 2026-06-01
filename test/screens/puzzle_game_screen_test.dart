import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pet_companion_app/screens/puzzle_game_screen.dart';

void main() {
  testWidgets('小螢幕顯示「選一張照片來玩拼圖」入口，不 overflow / 不 crash',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: PuzzleGameScreen()));
    await tester.pump();

    expect(find.text('照片拼圖'), findsOneWidget); // AppBar
    expect(find.text('選一張照片來玩拼圖'), findsOneWidget);
    expect(find.text('從相簿選照片'), findsOneWidget);
    // 任何 RenderFlex overflow 都會讓 takeException 非 null。
    expect(tester.takeException(), isNull);
  });
}
