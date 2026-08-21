import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pet_companion_app/widgets/conversation_bubble_stack.dart';

void main() {
  testWidgets('empty conversation shows elder-friendly voice prompt',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ConversationBubbleStack(
            userText: '',
            temporaryUserText: '',
            temporaryUserStatus: '',
            petText: '',
            petName: '咕咕',
            isWaiting: false,
            compact: true,
          ),
        ),
      ),
    );

    expect(find.text('可以這樣說'), findsOneWidget);
    expect(find.textContaining('按下面麥克風'), findsOneWidget);
    expect(find.textContaining('提醒我吃藥'), findsOneWidget);
    expect(find.textContaining('今天心情不好'), findsOneWidget);
    expect(find.textContaining('debug'), findsNothing);
    expect(find.textContaining('error'), findsNothing);
    expect(find.textContaining('Realtime'), findsNothing);
  });
}
