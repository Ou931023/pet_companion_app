import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pet_companion_app/controllers/care_alert_controller.dart';
import 'package:pet_companion_app/models/care_alert.dart';
import 'package:pet_companion_app/screens/care_alert_screen.dart';
import 'package:pet_companion_app/services/care_alert_storage_service.dart';

CareAlert _alert(String id, CareAlertRiskLevel level, String summary) {
  return CareAlert(
    id: id,
    createdAt: DateTime(2026, 5, 31, 10),
    riskLevel: level,
    category: CareAlertCategory.other,
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

  testWidgets('#3/#4 medium/high/urgent 顯示為 持續觀察/需通知/緊急，並顯示 triggerSummary',
      (tester) async {
    final controller = CareAlertController(CareAlertStorageService());
    await controller.loadAlerts();
    await controller.addAlert(
      _alert('m', CareAlertRiskLevel.medium, '系統偵測長者提到睡眠不佳，建議持續觀察近況。'),
    );
    await controller.addAlert(
      _alert('h', CareAlertRiskLevel.high, '系統偵測長者情緒低落，建議照護人員主動關心。'),
    );
    await controller.addAlert(
      _alert('u', CareAlertRiskLevel.urgent, '系統偵測長者疑似跌倒，建議立即確認安全。'),
    );

    await _pumpScreen(tester, controller);

    expect(find.text('持續觀察'), findsOneWidget);
    expect(find.text('需通知'), findsOneWidget);
    expect(find.text('緊急'), findsOneWidget);

    // triggerSummary 有清楚顯示
    expect(find.textContaining('持續觀察近況'), findsOneWidget);
    expect(find.textContaining('立即確認安全'), findsOneWidget);
  });

  testWidgets('長者友善：care alert 畫面不出現工程 / debug 字樣', (tester) async {
    final controller = CareAlertController(CareAlertStorageService());
    await controller.loadAlerts();
    await controller.addAlert(
      _alert('m', CareAlertRiskLevel.medium, '系統偵測長者提到睡眠不佳，建議持續觀察近況。'),
    );

    await _pumpScreen(tester, controller);

    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join('\n');

    const banned = [
      'riskLevel',
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
