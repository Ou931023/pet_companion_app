import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/models/companion_reply.dart';
import 'package:pet_companion_app/widgets/companion_debug_panel.dart';

void main() {
  testWidgets('CompanionDebugPanel shows latest strategy debug info',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CompanionDebugPanel(
            info: CompanionReplyDebugInfo(
              detectedEmotion: 'lonely',
              fusedEmotion: 'lonely',
              companionMode: 'emotional_companion',
              petExpression: 'concerned',
              petAction: 'move_closer',
              userStateHints: UserStateHints(
                mentionedLonely: true,
                mentionedTired: false,
                mentionedPoorSleep: true,
                mentionedLowAppetite: false,
                mentionedPainOrDiscomfort: false,
              ),
              referencedPreviousState: true,
              optionalSuggestionDeferred: true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('detectedEmotion'), findsOneWidget);
    expect(find.text('lonely'), findsWidgets);
    expect(find.text('companionMode'), findsOneWidget);
    expect(find.text('emotional_companion'), findsOneWidget);
    expect(find.text('petExpression'), findsOneWidget);
    expect(find.text('concerned'), findsOneWidget);
    expect(find.text('petAction'), findsOneWidget);
    expect(find.text('move_closer'), findsOneWidget);
    expect(find.text('mentionedLonely: true'), findsOneWidget);
    expect(find.text('mentionedPoorSleep: true'), findsOneWidget);
    expect(find.text('引用前一輪狀態'), findsOneWidget);
    expect(find.text('optionalSuggestion 延後/壓低'), findsOneWidget);
    expect(find.text('是'), findsNWidgets(2));
  });
}
