import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pet_companion_app/widgets/conversation_bubble_stack.dart';
import 'package:pet_companion_app/widgets/text_conversation_bar.dart';

void main() {
  testWidgets('shows temporary user bubble for transcript delta',
      (tester) async {
    await tester.pumpWidget(_bubbleHost(
      temporaryUserText: '今天家裡',
      temporaryUserStatus: '聆聽中',
    ));

    expect(find.byKey(const ValueKey('temporary-user-message-bubble')),
        findsOneWidget);
    expect(find.text('今天家裡'), findsOneWidget);
    expect(find.text('你說・聆聽中'), findsOneWidget);
  });

  testWidgets('commits completed transcript and clears temporary bubble',
      (tester) async {
    await tester.pumpWidget(_bubbleHost(
      userText: '今天家裡好安靜',
    ));

    expect(find.byKey(const ValueKey('temporary-user-message-bubble')),
        findsNothing);
    expect(find.byKey(const ValueKey('latest-user-message-bubble')),
        findsOneWidget);
    expect(find.text('今天家裡好安靜'), findsOneWidget);
  });

  testWidgets('shows draft bubble while typing', (tester) async {
    await tester.pumpWidget(const _DraftHarness());

    await tester.enterText(find.byType(TextField), '我想聊聊天');
    await tester.pump();

    expect(find.byKey(const ValueKey('temporary-user-message-bubble')),
        findsOneWidget);
    expect(find.text('我想聊聊天'), findsWidgets);
    expect(find.text('你說・輸入中'), findsOneWidget);
  });

  testWidgets('sending text clears draft bubble and shows formal message',
      (tester) async {
    await tester.pumpWidget(const _DraftHarness());

    await tester.enterText(find.byType(TextField), '謝謝你陪我');
    await tester.pump();
    await tester.tap(find.byTooltip('送出'));
    await tester.pump();

    expect(find.byKey(const ValueKey('temporary-user-message-bubble')),
        findsNothing);
    expect(find.byKey(const ValueKey('latest-user-message-bubble')),
        findsOneWidget);
    expect(find.text('謝謝你陪我'), findsOneWidget);
  });

  testWidgets('speech partial and draft do not become two formal messages',
      (tester) async {
    await tester.pumpWidget(_bubbleHost(
      userText: '正式訊息',
      temporaryUserText: '語音 partial',
      temporaryUserStatus: '聆聽中',
    ));

    expect(find.byKey(const ValueKey('latest-user-message-bubble')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('temporary-user-message-bubble')),
        findsOneWidget);
    expect(find.text('正式訊息'), findsOneWidget);
    expect(find.text('語音 partial'), findsOneWidget);
  });

  testWidgets('empty final transcript does not create a formal user bubble',
      (tester) async {
    await tester.pumpWidget(_bubbleHost());

    expect(find.byKey(const ValueKey('temporary-user-message-bubble')),
        findsNothing);
    expect(
        find.byKey(const ValueKey('latest-user-message-bubble')), findsNothing);
  });

  testWidgets('petText over 80 Chinese chars does not overflow',
      (tester) async {
    final longPetText = List.filled(
      7,
      '我在這裡陪你慢慢說，先不用急著把所有事情一次講完。',
    ).join();

    await tester.pumpWidget(_bubbleHost(petText: longPetText));

    expect(tester.takeException(), isNull);
    final petTextWidget = tester.widget<Text>(find.text(longPetText));
    expect(petTextWidget.maxLines, 6);
  });

  testWidgets('userText over 60 Chinese chars does not overflow',
      (tester) async {
    final longUserText = List.filled(
      5,
      '今仔日厝內足安靜我想慢慢講予你聽但是心內有真濟話。',
    ).join();

    await tester.pumpWidget(_bubbleHost(userText: longUserText));

    expect(tester.takeException(), isNull);
    final userTextWidget = tester.widget<Text>(find.text(longUserText));
    expect(userTextWidget.maxLines, 6);
  });

  testWidgets('temporaryUserText stays short while transcribing',
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
    final partialTextWidget = tester.widget<Text>(find.text(longPartialText));
    expect(partialTextWidget.maxLines, 3);
  });
}

Widget _bubbleHost({
  String userText = '',
  String temporaryUserText = '',
  String temporaryUserStatus = '',
  String petText = '我在這裡陪你。',
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
                petText: '我在這裡陪你。',
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
