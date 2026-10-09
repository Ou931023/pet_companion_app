import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AndroidFlutterLocalNotificationsPlugin.registerWith();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  late FlutterLocalNotificationsPlatform originalPlatform;
  late List<MethodCall> calls;
  bool? exactAllowed;
  bool revokedBeforeSchedule = false;
  String? otherError;

  setUp(() {
    originalPlatform = FlutterLocalNotificationsPlatform.instance;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    calls = [];
    exactAllowed = true;
    revokedBeforeSchedule = false;
    otherError = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'initialize') return true;
      if (call.method == 'canScheduleExactNotifications') return exactAllowed;
      if (call.method == 'zonedSchedule') {
        if (otherError != null) throw PlatformException(code: otherError!);
        final arguments = Map<dynamic, dynamic>.from(call.arguments as Map);
        final mode = (arguments['platformSpecifics'] as Map)['scheduleMode'];
        if (mode == 'exactAllowWhileIdle' &&
            (exactAllowed != true || revokedBeforeSchedule)) {
          throw PlatformException(code: 'exact_alarms_not_permitted');
        }
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    FlutterLocalNotificationsPlatform.instance = originalPlatform;
    debugDefaultTargetPlatformOverride = null;
  });

  List<String> scheduleModes() => calls
      .where((call) => call.method == 'zonedSchedule')
      .map((call) =>
          ((call.arguments as Map)['platformSpecifics'] as Map)['scheduleMode']
              as String)
      .toList();

  void expectRealSchedulingWithoutPermissionRequests() {
    expect(calls.where((call) => call.method == 'initialize'), hasLength(1));
    expect(calls.where((call) => call.method == 'zonedSchedule'), isNotEmpty);
    expect(calls.where((call) => call.method.startsWith('request')), isEmpty);
    for (final call in calls.where((call) => call.method == 'zonedSchedule')) {
      expect((call.arguments as Map)['id'], 10001);
      expect((call.arguments as Map)['payload'], 'check_in_reminder');
    }
  }

  test('denied exact alarms schedules optional check-in inexactly and startup continues',
      () async {
    exactAllowed = false;
    var continued = false;
    await NotificationService().syncCheckInReminder(hasCheckedInToday: false);
    continued = true;
    expect(continued, isTrue);
    expect(scheduleModes(), ['inexactAllowWhileIdle']);
    expectRealSchedulingWithoutPermissionRequests();
  });

  test('unknown exact capability conservatively uses inexact check-in', () async {
    exactAllowed = null;
    await NotificationService().syncCheckInReminder(hasCheckedInToday: true);
    expect(scheduleModes(), ['inexactAllowWhileIdle']);
    expectRealSchedulingWithoutPermissionRequests();
  });

  test('permitted exact alarms retain exact check-in scheduling', () async {
    await NotificationService().syncCheckInReminder(hasCheckedInToday: false);
    expect(scheduleModes(), ['exactAllowWhileIdle']);
    expectRealSchedulingWithoutPermissionRequests();
  });

  test('revocation between capability check and scheduling retries once inexactly',
      () async {
    revokedBeforeSchedule = true;
    await NotificationService().syncCheckInReminder(hasCheckedInToday: false);
    expect(scheduleModes(), ['exactAllowWhileIdle', 'inexactAllowWhileIdle']);
    expectRealSchedulingWithoutPermissionRequests();
  });

  test('unrelated scheduling failures remain observable and are not retried', () async {
    otherError = 'synthetic_other_failure';
    await expectLater(
      NotificationService().syncCheckInReminder(hasCheckedInToday: false),
      throwsA(isA<PlatformException>().having(
        (error) => error.code,
        'code',
        'synthetic_other_failure',
      )),
    );
    expect(scheduleModes(), ['exactAllowWhileIdle']);
  });
}
