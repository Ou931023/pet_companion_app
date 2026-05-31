import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/widgets/feature_tour.dart';

Future<void> _pumpTour(
  WidgetTester tester, {
  required VoidCallback onFinish,
  VoidCallback? onSkip,
  String finishLabel = '開始使用',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: FeatureTourView(
        pages: featureTourPages,
        onFinish: onFinish,
        onSkip: onSkip,
        finishLabel: finishLabel,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void useTallView(WidgetTester tester) {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
  }

  testWidgets('第一頁：顯示標題、下一個、略過；沒有上一個', (tester) async {
    useTallView(tester);
    await _pumpTour(tester, onFinish: () {});

    expect(find.text(featureTourPages.first.title), findsOneWidget);
    expect(find.text('下一個'), findsOneWidget);
    expect(find.text('略過'), findsOneWidget);
    expect(find.text('上一個'), findsNothing);
  });

  testWidgets('逐頁前進到最後一頁顯示 finishLabel，按下呼叫 onFinish', (tester) async {
    useTallView(tester);
    var finished = false;
    await _pumpTour(tester, onFinish: () => finished = true, finishLabel: '開始使用');

    for (var i = 0; i < featureTourPages.length - 1; i += 1) {
      await tester.tap(find.text('下一個'));
      await tester.pumpAndSettle();
    }
    // 最後一頁
    expect(find.text(featureTourPages.last.title), findsOneWidget);
    expect(find.text('開始使用'), findsOneWidget);
    expect(find.text('下一個'), findsNothing);
    expect(find.text('上一個'), findsOneWidget);

    await tester.tap(find.text('開始使用'));
    await tester.pumpAndSettle();
    expect(finished, isTrue);
  });

  testWidgets('略過呼叫 onSkip（不呼叫 onFinish）', (tester) async {
    useTallView(tester);
    var skipped = false;
    var finished = false;
    await _pumpTour(
      tester,
      onFinish: () => finished = true,
      onSkip: () => skipped = true,
    );

    await tester.tap(find.text('略過'));
    await tester.pump();
    expect(skipped, isTrue);
    expect(finished, isFalse);
  });

  test('導覽內容不含工程 / 監控 / 警報字眼', () {
    const forbidden = [
      'debug',
      'Debug',
      'JSON',
      'json',
      'riskLevel',
      'triggerSummary',
      '監控',
      '警報',
    ];
    for (final page in featureTourPages) {
      final text = '${page.title} ${page.body}';
      for (final word in forbidden) {
        expect(text.contains(word), isFalse, reason: '導覽不應出現「$word」');
      }
    }
  });

  test('涵蓋需求指定的白話說明句', () {
    final all = featureTourPages.map((p) => '${p.title}｜${p.body}').join('\n');
    expect(all.contains('協助提醒照護人員'), isTrue, reason: '應有 Care Alert 白話說明');
    expect(all.contains('背包'), isTrue, reason: '應有背包/寵物狀態說明');
    expect(all.contains('問號'), isTrue, reason: '應提示首頁問號可再看一次');
    expect(all.contains('麥克風'), isTrue, reason: '應有語音對話說明');
  });
}
