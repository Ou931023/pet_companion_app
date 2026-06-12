import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pet_companion_app/widgets/conversation_bubble_stack.dart';
import 'package:pet_companion_app/widgets/text_conversation_bar.dart';

void main() {
  testWidgets('transcript delta shows live in the unified bubble',
      (tester) async {
    await tester.pumpWidget(_bubbleHost(
      temporaryUserText: '今天家裡',
      temporaryUserStatus: '聆聽中',
    ));

    expect(find.byKey(const ValueKey('latest-pet-message-bubble')),
        findsOneWidget);
    expect(find.text('今天家裡'), findsOneWidget);
    expect(find.text('你說・聆聽中'), findsOneWidget);
  });

  testWidgets('finalized user transcript shows in the unified bubble',
      (tester) async {
    await tester.pumpWidget(_bubbleHost(
      userText: '今天家裡好安靜',
    ));

    expect(find.byKey(const ValueKey('latest-pet-message-bubble')),
        findsOneWidget);
    expect(find.text('今天家裡好安靜'), findsOneWidget);
    expect(find.text('你說'), findsOneWidget);
  });

  testWidgets('typing in draft shows live in the unified bubble',
      (tester) async {
    await tester.pumpWidget(const _DraftHarness());

    await tester.enterText(find.byType(TextField), '我想聊聊天');
    await tester.pump();

    expect(find.byKey(const ValueKey('latest-pet-message-bubble')),
        findsOneWidget);
    expect(find.text('我想聊聊天'), findsWidgets);
    expect(find.text('你說・輸入中'), findsOneWidget);
  });

  testWidgets('sending text replaces draft with formal user content',
      (tester) async {
    await tester.pumpWidget(const _DraftHarness());

    await tester.enterText(find.byType(TextField), '謝謝你陪我');
    await tester.pump();
    await tester.tap(find.byTooltip('送出'));
    await tester.pump();

    expect(find.byKey(const ValueKey('latest-pet-message-bubble')),
        findsOneWidget);
    expect(find.text('謝謝你陪我'), findsOneWidget);
    expect(find.text('你說・輸入中'), findsNothing);
  });

  testWidgets('pet reply takes priority over user content',
      (tester) async {
    await tester.pumpWidget(_bubbleHost(
      userText: '使用者最終文字',
      temporaryUserText: '語音 partial',
      temporaryUserStatus: '聆聽中',
      petText: '我在這裡陪你。',
    ));

    expect(find.byKey(const ValueKey('latest-pet-message-bubble')),
        findsOneWidget);
    expect(find.text('我在這裡陪你。'), findsOneWidget);
    expect(find.text('小伴'), findsOneWidget);
    expect(find.text('使用者最終文字'), findsNothing);
    expect(find.text('語音 partial'), findsNothing);
  });

  testWidgets('final user text shown above partial when both set',
      (tester) async {
    await tester.pumpWidget(_bubbleHost(
      userText: '正式訊息',
      temporaryUserText: '語音 partial',
      temporaryUserStatus: '聆聽中',
    ));

    expect(find.text('正式訊息'), findsOneWidget);
    expect(find.text('語音 partial'), findsNothing);
    expect(find.text('你說'), findsOneWidget);
  });

  testWidgets('empty everything renders a placeholder bubble', (tester) async {
    await tester.pumpWidget(_bubbleHost());

    expect(find.byKey(const ValueKey('latest-pet-message-bubble')),
        findsOneWidget);
  });

  testWidgets(
      'petText over 80 Chinese chars paginates without overflow (CR-0080)',
      (tester) async {
    final longPetText = List.filled(
      7,
      '我在這裡陪你慢慢說，先不用急著把所有事情一次講完。',
    ).join();

    await tester.pumpWidget(_bubbleHost(petText: longPetText));
    await tester.pump();

    // 不會 overflow，且不會把整段塞進單一 Text（已分頁）。
    expect(tester.takeException(), isNull);
    expect(find.text(longPetText), findsNothing);
    expect(find.byKey(const ValueKey('latest-pet-message-bubble')),
        findsOneWidget);

    // 排空所有自動翻頁計時器（最後一頁不再排程），避免 pending timer。
    await tester.pump(const Duration(seconds: 90));
    expect(tester.takeException(), isNull);
  });

  testWidgets('userText over 60 Chinese chars renders without overflow',
      (tester) async {
    final longUserText = List.filled(
      5,
      '今仔日厝內足安靜我想慢慢講予你聽但是心內有真濟話。',
    ).join();

    await tester.pumpWidget(_bubbleHost(userText: longUserText));

    expect(tester.takeException(), isNull);
    expect(find.text(longUserText), findsOneWidget);
  });

  testWidgets('temporaryUserText renders without throwing when long',
      (tester) async {
    final longPartialText = List.filled(
      5,
      '我正在講一段很長的語音辨識內容還沒有完成。',
    ).join();

    await tester.pumpWidget(_bubbleHost(
      temporaryUserText: longPartialText,
      temporaryUserStatus: '辨識中',
    ));

    expect(tester.takeException(), isNull);
    expect(find.text(longPartialText), findsOneWidget);
  });
}

Widget _bubbleHost({
  String userText = '',
  String temporaryUserText = '',
  String temporaryUserStatus = '',
  String petText = '',
  bool compact = false,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ConversationBubbleStack(
          userText: userText,
          temporaryUserText: temporaryUserText,
          temporaryUserStatus: temporaryUserStatus,
          petText: petText,
          petName: '小伴',
          isWaiting: false,
          compact: compact,
        ),
      ),
    ),
  );
}

class _DraftHarness extends StatefulWidget {
  const _DraftHarness();

  @override
  State<_DraftHarness> createState() => _DraftHarnessState();
}

class _DraftHarnessState extends State<_DraftHarness> {
  final _controller = TextEditingController();
  String _draft = '';
  String _formal = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              ConversationBubbleStack(
                userText: _formal,
                temporaryUserText: _draft,
                temporaryUserStatus: _draft.trim().isEmpty ? '' : '輸入中',
                petText: '',
                petName: '小伴',
                isWaiting: false,
                compact: false,
              ),
              TextConversationBar(
                controller: _controller,
                enabled: true,
                isBusy: false,
                onChanged: (value) => setState(() => _draft = value.trim()),
                onSend: (value) {
                  final normalized = value.trim();
                  if (normalized.isEmpty) return;
                  setState(() {
                    _formal = normalized;
                    _draft = '';
                    _controller.clear();
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
