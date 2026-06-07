import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pet_companion_app/controllers/care_alert_controller.dart';
import 'package:pet_companion_app/models/care_alert.dart';
import 'package:pet_companion_app/screens/care_alert_screen.dart';
import 'package:pet_companion_app/services/care_alert_storage_service.dart';

CareAlert _alert(
  String id,
  CareAlertRiskLevel level,
  String summary, {
  CareAlertCategory category = CareAlertCategory.other,
}) {
  return CareAlert(
    id: id,
    createdAt: DateTime(2026, 5, 31, 10),
    riskLevel: level,
    category: category,
    triggerSummary: summary,
    transcriptSnippet: '對話片段',
    source: 'companion_analysis',
    isRead: false,
  );
}

Future<void> _pumpScreen(
  WidgetTester tester,
  CareAlertController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ChangeNotifierProvider<CareAlertController>.value(
        value: controller,
        child: const CareAlertScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('長者端：標題溫暖，且呈現「有人關心你」與白話確認按鈕', (tester) async {
    final controller = CareAlertController(CareAlertStorageService());
    await controller.loadAlerts();
    await controller.addAlert(
      _alert('m', CareAlertRiskLevel.medium, '系統偵測長者提到睡眠不佳，建議持續觀察近況。',
          category: CareAlertCategory.sleep),
    );

    await _pumpScreen(tester, controller);

    expect(find.text('今日關心紀錄'), findsOneWidget); // AppBar 標題
    expect(find.text('有人關心你'), findsWidgets);
    expect(find.text('我知道了，謝謝你'), findsOneWidget);
  });

  testWidgets('長者端：不顯示風險等級、分析摘要與原始對話（那些只給照護端）',
      (tester) async {
    final controller = CareAlertController(CareAlertStorageService());
    await controller.loadAlerts();
    await controller.addAlert(
      _alert('m', CareAlertRiskLevel.medium, '系統偵測長者提到睡眠不佳，建議持續觀察近況。',
          category: CareAlertCategory.sleep),
    );
    await controller.addAlert(
      _alert('h', CareAlertRiskLevel.high, '系統偵測長者情緒低落，建議照護人員主動關心。',
          category: CareAlertCategory.depressed),
    );
    await controller.addAlert(
      _alert('u', CareAlertRiskLevel.urgent, '系統偵測長者疑似跌倒，建議立即確認安全。',
          category: CareAlertCategory.fall),
    );

    await _pumpScreen(tester, controller);

    // 風險等級代碼 / label 不應出現在長者端
    expect(find.text('持續觀察'), findsNothing);
    expect(find.text('需通知'), findsNothing);
    expect(find.text('緊急'), findsNothing);

    // 後台分析摘要 triggerSummary 不應出現
    expect(find.textContaining('持續觀察近況'), findsNothing);
    expect(find.textContaining('主動關心'), findsNothing);
    expect(find.textContaining('立即確認安全'), findsNothing);
    expect(find.textContaining('系統偵測'), findsNothing);

    // 原始對話片段不應原樣顯示給長者
    expect(find.textContaining('對話片段'), findsNothing);
  });

  testWidgets('長者友善：care alert 畫面不出現工程 / debug 字樣', (tester) async {
    final controller = CareAlertController(CareAlertStorageService());
    await controller.loadAlerts();
    await controller.addAlert(
      _alert('m', CareAlertRiskLevel.medium, '系統偵測長者提到睡眠不佳，建議持續觀察近況。',
          category: CareAlertCategory.sleep),
    );

    await _pumpScreen(tester, controller);

    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join('\n');

    const banned = [
      'riskLevel',
      'triggerSummary',
      'null',
      'Exception',
      'WebRTC',
      'DEBUG',
      'debug',
      'TODO',
      'companion_analysis',
    ];
    for (final word in banned) {
      expect(
        texts.contains(word),
        isFalse,
        reason: '長者畫面不應出現工程字「$word」',
      );
    }
  });
}
