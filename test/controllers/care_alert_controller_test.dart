import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pet_companion_app/controllers/care_alert_controller.dart';
import 'package:pet_companion_app/models/care_alert.dart';
import 'package:pet_companion_app/services/care_alert_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  CareAlert sampleAlert(String id, {int minute = 0, bool isRead = false}) {
    return CareAlert(
      id: id,
      createdAt: DateTime(2026, 5, 22, 9, minute),
      riskLevel: CareAlertRiskLevel.attention,
      category: CareAlertCategory.sleep,
      triggerSummary: '提到睡不好',
      transcriptSnippet: '我最近都睡不好',
      source: 'test',
      isRead: isRead,
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('addAlert increases the alert count', () async {
    final controller = CareAlertController(CareAlertStorageService());
    await controller.loadAlerts();
    expect(controller.alerts, isEmpty);

    await controller.addAlert(sampleAlert('a1'));

    expect(controller.alerts.length, 1);
    expect(controller.alerts.first.id, 'a1');
  });

  test('markAsRead sets isRead true and updates unreadCount', () async {
    final controller = CareAlertController(CareAlertStorageService());
    await controller.loadAlerts();
    await controller.addAlert(sampleAlert('a1', minute: 0));
    await controller.addAlert(sampleAlert('a2', minute: 1));
    expect(controller.unreadCount, 2);

    await controller.markAsRead('a1');

    final a1 = controller.alerts.firstWhere((alert) => alert.id == 'a1');
    expect(a1.isRead, isTrue);
    expect(controller.unreadCount, 1);
  });

  test('clearAllAlerts empties the list', () async {
    final controller = CareAlertController(CareAlertStorageService());
    await controller.loadAlerts();
    await controller.addAlert(sampleAlert('a1'));

    await controller.clearAllAlerts();

    expect(controller.alerts, isEmpty);
    expect(controller.unreadCount, 0);
  });

  test('alerts persist across reload via storage', () async {
    final storage = CareAlertStorageService();
    final controller = CareAlertController(storage);
    await controller.loadAlerts();
    await controller.addAlert(sampleAlert('a1'));

    final reloaded = CareAlertController(storage);
    await reloaded.loadAlerts();

    expect(reloaded.alerts.length, 1);
    expect(reloaded.alerts.first.id, 'a1');
  });
}
