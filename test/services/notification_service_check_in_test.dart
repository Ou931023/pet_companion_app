import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dexterous.com/flutter/local_notifications');

  group('NotificationService check-in（無平台外掛時不可 crash）', () {
    setUp(() {
      // 模擬「權限被拒 / 平台回傳 false」：所有原生呼叫都回 false，不丟例外。
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'requestPermissions' ||
            call.method == 'requestNotificationsPermission') {
          return false;
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('requestPermissions 權限被拒時回傳 false、不 crash', () async {
      final service = NotificationService();
      final granted = await service.requestPermissions();
      expect(granted, isFalse);
    });

    test('syncCheckInReminder 不會丟出例外（已簽到 / 未簽到都可呼叫）', () async {
      final service = NotificationService();
      await service.syncCheckInReminder(hasCheckedInToday: false);
      await service.syncCheckInReminder(hasCheckedInToday: true);
      await service.cancelTodayCheckInReminder();
      await service.cancelAllNotifications();
    });
  });
}
