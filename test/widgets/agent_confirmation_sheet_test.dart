import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/models/agent_tool_intent.dart';
import 'package:pet_companion_app/widgets/agent/agent_confirmation_sheet.dart';

/// 高風險工具（撥號 / 寄信 / 傳訊息）的確認 sheet。先前 sheet 從未被任何畫面叫出，
/// 導致需確認的工具設了 pendingIntent 卻沒有 UI 可確認、整個卡住（撥號「沒反應」）。
/// 這裡鎖住 sheet 的對外契約：顯示工具名 + 白話風險說明 + 「確認執行 / 取消」會回呼。
void main() {
  AgentToolIntent dialIntent() => AgentToolIntent(
        id: 'agent_tool_dial',
        toolName: 'open_phone_dialer',
        displayName: '開啟撥號畫面',
        arguments: const {'contactName': '兒子'},
        requiresConfirmation: true,
        riskLevel: AgentToolRiskLevel.high,
        status: AgentToolStatus.pending,
        userFacingMessage: '要幫你開啟撥號畫面嗎？不會自動撥出。',
        createdAt: DateTime(2026, 1, 1),
      );

  Future<void> pumpSheet(
    WidgetTester tester, {
    required VoidCallback onConfirm,
    required VoidCallback onCancel,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentConfirmationSheet(
            intent: dialIntent(),
            onConfirm: onConfirm,
            onCancel: onCancel,
          ),
        ),
      ),
    );
  }

  testWidgets('顯示工具名、白話風險說明與「不會自動撥出」提醒', (tester) async {
    await pumpSheet(tester, onConfirm: () {}, onCancel: () {});
    expect(find.text('開啟撥號畫面'), findsOneWidget);
    expect(find.textContaining('高風險'), findsOneWidget);
    expect(find.textContaining('不會自動撥出'), findsOneWidget);
    expect(find.text('確認執行'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
  });

  testWidgets('按「確認執行」呼叫 onConfirm，不呼叫 onCancel', (tester) async {
    var confirmed = 0;
    var cancelled = 0;
    await pumpSheet(
      tester,
      onConfirm: () => confirmed++,
      onCancel: () => cancelled++,
    );
    await tester.tap(find.text('確認執行'));
    await tester.pump();
    expect(confirmed, 1);
    expect(cancelled, 0);
  });

  testWidgets('按「取消」呼叫 onCancel，不呼叫 onConfirm', (tester) async {
    var confirmed = 0;
    var cancelled = 0;
    await pumpSheet(
      tester,
      onConfirm: () => confirmed++,
      onCancel: () => cancelled++,
    );
    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(cancelled, 1);
    expect(confirmed, 0);
  });
}
