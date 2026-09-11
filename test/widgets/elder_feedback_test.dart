import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/widgets/ui/elder_feedback.dart';

void main() {
  tearDown(ElderFeedback.hide);

  testWidgets('一般提示同時只有一則，新訊息會取代舊訊息', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );

    ElderFeedback.show(context, '已換成真實版');
    await tester.pump();
    expect(find.text('已換成真實版'), findsOneWidget);

    ElderFeedback.show(context, '已換成 Q 版');
    await tester.pump();
    expect(find.text('已換成真實版'), findsNothing);
    expect(find.text('已換成 Q 版'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    expect(find.text('已換成 Q 版'), findsNothing);
  });

  testWidgets('重要提示有清楚的知道了按鈕與 live region', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );

    ElderFeedback.showImportant(context, '現在連線不太穩，請再試一次。');
    await tester.pumpAndSettle();

    expect(find.text('現在連線不太穩，請再試一次。'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '知道了'), findsOneWidget);
    final semantics = tester.getSemantics(
      find.text('現在連線不太穩，請再試一次。'),
    );
    expect(semantics.flagsCollection.isLiveRegion, isTrue);

    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(find.text('現在連線不太穩，請再試一次。'), findsNothing);
  });

  testWidgets('切換頁面時會移除上一頁的一般提示', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    late BuildContext firstPageContext;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: Builder(
          builder: (context) {
            firstPageContext = context;
            return const Scaffold(body: Text('第一頁'));
          },
        ),
      ),
    );

    ElderFeedback.show(firstPageContext, '上一頁的提示');
    await tester.pump();
    expect(find.text('上一頁的提示'), findsOneWidget);

    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('第二頁')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('第二頁'), findsOneWidget);
    expect(find.text('上一頁的提示'), findsNothing);
  });
}
