import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pet_companion_app/screens/register_screen.dart';

Future<void> _pumpRegister(
  WidgetTester tester, {
  VoidCallback? onBackToLogin,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: RegisterScreen(onBackToLogin: onBackToLogin),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 放大測試視窗，避免長者友善大字大按鈕在預設小視窗下被裁掉。
  void useTallView(WidgetTester tester) {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
  }

  testWidgets('顯示溫暖標題、副標與三種綁定選項', (tester) async {
    useTallView(tester);
    await _pumpRegister(tester);

    expect(find.text('建立你的帳號，紀錄好好保存'), findsOneWidget);
    expect(find.text('綁定一個常用的帳號，下次回來陪伴的點滴都還在。'), findsOneWidget);
    expect(find.text('用 Google 註冊'), findsOneWidget);
    expect(find.text('用 Apple 註冊'), findsOneWidget);
    expect(find.text('用 Email 註冊'), findsOneWidget);
  });

  testWidgets('綁定按鈕點擊不 crash 並顯示「即將推出」', (tester) async {
    useTallView(tester);
    await _pumpRegister(tester);

    await tester.tap(find.text('用 Google 註冊'));
    await tester.pump();

    expect(find.textContaining('即將推出'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('點「返回登入」會呼叫 onBackToLogin', (tester) async {
    useTallView(tester);
    var backTapped = false;
    await _pumpRegister(tester, onBackToLogin: () => backTapped = true);

    await tester.tap(find.text('返回登入'));
    await tester.pump();

    expect(backTapped, isTrue);
  });
}
