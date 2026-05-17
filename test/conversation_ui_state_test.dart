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

  testWidgets('empty final transcript does not create a formal user bubble',
      (tester) async {
    await tester.pumpWidget(_bubbleHost());

    expect(find.byKey(const ValueKey('temporary-user-message-bubble')),
        findsNothing);
    expect(
        find.byKey(const ValueKey('latest-user-message-bubble')), findsNothing);
  });
}

Widget _bubbleHost({
  String userText = '',
  String temporaryUserText = '',
  String temporaryUserStatus = '',
}) {
  return MaterialApp(
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ConversationBubbleStack(
          userText: userText,
          temporaryUserText: temporaryUserText,
          temporaryUserStatus: temporaryUserStatus,
          petText: '我在這裡陪你。',
          petName: '小伴',
          isWaiting: false,
          compact: false,
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
