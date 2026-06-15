import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/services/notification_service.dart';

// CR-0087：NotificationService 寵物關心提醒薄封裝在無平台外掛時不可 crash，
// 且不得影響既有簽到提醒方法。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dexterous.com/flutter/local_notifications');

  group('NotificationService 寵物關心提醒（無平台外掛時不可 crash）', () {
    setUp(() {
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

    test('schedulePetConcernReminder / cancel 不丟例外', () async {
      final service = NotificationService();
      await service.schedulePetConcernReminder(
        title: '小夥伴有點擔心你',
        body: '想陪你說說話。',
        scheduledAt: DateTime.now().add(const Duration(hours: 2)),
      );
      await service.cancelPetConcernReminder();
    });

    test('關心提醒與簽到提醒互不干擾（都可呼叫、都不 crash）', () async {
      final service = NotificationService();
      await service.syncCheckInReminder(hasCheckedInToday: false);
      await service.schedulePetConcernReminder(
        title: '寵物肚子餓了',
        body: '回來看看牠吧！',
        scheduledAt: DateTime.now().add(const Duration(hours: 1)),
      );
      await service.cancelPetConcernReminder();
      // 簽到提醒仍可獨立取消，不受影響。
      await service.cancelTodayCheckInReminder();
    });
  });
}
