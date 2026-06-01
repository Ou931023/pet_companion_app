import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/controllers/app_navigation_controller.dart';
import 'package:pet_companion_app/controllers/memory_controller.dart';
import 'package:pet_companion_app/controllers/reminder_controller.dart';
import 'package:pet_companion_app/models/agent_tool_intent.dart';
import 'package:pet_companion_app/models/reminder.dart';
import 'package:pet_companion_app/routes/app_routes.dart';
import 'package:pet_companion_app/services/memory_service.dart';
import 'package:pet_companion_app/services/native_tool_executor_service.dart';
import 'package:pet_companion_app/services/notification_service.dart';
import 'package:pet_companion_app/services/reminder_service.dart';
import 'package:pet_companion_app/services/search_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('unknown tool is rejected', () async {
    final service = NativeToolExecutorService(launch: (_, __) async => true);
    final result = await service.execute(
      intent: _intent('unknown_tool'),
      reminderController: _FakeReminderController(),
      searchService: SearchService(),
      navigationController: AppNavigationController(),
      memoryController: _memoryController(),
    );

    expect(result.success, isFalse);
    expect(result.message, contains('不支援'));
  });

  test('phone dialer uses tel scheme without auto dialing', () async {
    Uri? launched;
    final service = NativeToolExecutorService(
      launch: (uri, mode) async {
        launched = uri;
        expect(mode, LaunchMode.externalApplication);
        return true;
      },
    );
    final result = await service.execute(
      intent: _intent(
        'open_phone_dialer',
        riskLevel: AgentToolRiskLevel.high,
        requiresConfirmation: true,
        arguments: {'phoneNumber': '0912345678'},
      ),
      reminderController: _FakeReminderController(),
      searchService: SearchService(),
      navigationController: AppNavigationController(),
      memoryController: _memoryController(),
    );

    expect(result.success, isTrue, reason: result.message);
    expect(launched?.scheme, 'tel');
    expect(launched?.path, '0912345678');
  });

  test('create reminder delegates to reminder controller', () async {
    final reminderController = _FakeReminderController();
    final service = NativeToolExecutorService(launch: (_, __) async => true);
    final result = await service.execute(
      intent: _intent(
        'create_reminder',
        riskLevel: AgentToolRiskLevel.medium,
        requiresConfirmation: true,
        arguments: {'text': '提醒我晚上八點吃藥'},
      ),
      reminderController: reminderController,
      searchService: SearchService(),
      navigationController: AppNavigationController(),
      memoryController: _memoryController(),
    );

    expect(result.success, isTrue, reason: result.message);
    expect(reminderController.createdText, '提醒我晚上八點吃藥');
  });

  test('工具丟例外時回白話訊息，不洩漏 exception / 原始錯誤', () async {
    final service = NativeToolExecutorService(launch: (_, __) async => true);
    final result = await service.execute(
      intent: _intent(
        'create_reminder',
        arguments: {'text': '提醒我吃藥'},
      ),
      reminderController: _ThrowingReminderController(),
      searchService: SearchService(),
      navigationController: AppNavigationController(),
      memoryController: _memoryController(),
    );

    expect(result.success, isFalse);
    expect(result.message, '這個動作暫時沒辦法完成，待會再試一次好嗎？');

    // 使用者看到的訊息不可夾帶任何例外原文 / 工程字。
    final msg = result.message;
    expect(msg.contains('secret-stack-detail'), isFalse);
    expect(msg.contains('Exception'), isFalse);
    expect(msg.toLowerCase().contains('error'), isFalse);
    expect(msg.toLowerCase().contains('failed'), isFalse);
    expect(msg.contains('工具執行失敗'), isFalse);
    expect(msg.contains('\$error'), isFalse);
  });

  test('open app route uses navigation whitelist', () async {
    final navigation = AppNavigationController();
    final service = NativeToolExecutorService(launch: (_, __) async => true);
    final result = await service.execute(
      intent: _intent(
        'open_app_route',
        arguments: {'route': AppRoute.shop},
      ),
      reminderController: _FakeReminderController(),
      searchService: SearchService(),
      navigationController: navigation,
      memoryController: _memoryController(),
    );

    expect(result.success, isTrue, reason: result.message);
    expect(navigation.currentShellRoute, AppRoute.shop);
  });

  test('send_message opens sms scheme with body, does not auto-send', () async {
    Uri? launched;
    final service = NativeToolExecutorService(
      launch: (uri, mode) async {
        launched = uri;
        return true;
      },
    );
    final result = await service.execute(
      intent: _intent(
        'send_message',
        riskLevel: AgentToolRiskLevel.high,
        requiresConfirmation: true,
        arguments: {'phoneNumber': '0912345678', 'body': '我今天很好'},
      ),
      reminderController: _FakeReminderController(),
      searchService: SearchService(),
      navigationController: AppNavigationController(),
      memoryController: _memoryController(),
    );

    expect(result.success, isTrue, reason: result.message);
    expect(launched?.scheme, 'sms');
    expect(launched?.path, '0912345678');
    expect(launched?.queryParameters['body'], '我今天很好');
  });

  test('logout delegates to injected onLogout callback', () async {
    var loggedOut = false;
    final service = NativeToolExecutorService(
      launch: (_, __) async => true,
      onLogout: () async {
        loggedOut = true;
      },
    );
    final result = await service.execute(
      intent: _intent('logout',
          riskLevel: AgentToolRiskLevel.high, requiresConfirmation: true),
      reminderController: _FakeReminderController(),
      searchService: SearchService(),
      navigationController: AppNavigationController(),
      memoryController: _memoryController(),
    );

    expect(loggedOut, isTrue);
    expect(result.success, isTrue, reason: result.message);
  });

  test('notify_caregiver delegates to injected callback (reuses care alert)',
      () async {
    String? capturedReason;
    final service = NativeToolExecutorService(
      launch: (_, __) async => true,
      onNotifyCaregiver: ({required reason, required riskLevel}) async {
        capturedReason = reason;
        return true;
      },
    );
    final result = await service.execute(
      intent: _intent(
        'notify_caregiver',
        riskLevel: AgentToolRiskLevel.high,
        requiresConfirmation: true,
        arguments: {'reason': '長者覺得不太舒服', 'riskLevel': 'high'},
      ),
      reminderController: _FakeReminderController(),
      searchService: SearchService(),
      navigationController: AppNavigationController(),
      memoryController: _memoryController(),
    );

    expect(capturedReason, '長者覺得不太舒服');
    expect(result.success, isTrue, reason: result.message);
  });

  test('delete_memory delegates to memory controller forgetRecent', () async {
    final memory = _SpyMemoryController();
    final service = NativeToolExecutorService(launch: (_, __) async => true);
    final result = await service.execute(
      intent: _intent('delete_memory',
          riskLevel: AgentToolRiskLevel.high, requiresConfirmation: true),
      reminderController: _FakeReminderController(),
      searchService: SearchService(),
      navigationController: AppNavigationController(),
      memoryController: memory,
    );

    expect(memory.forgetCalled, isTrue);
    expect(result.success, isTrue, reason: result.message);
  });

  test('tell_story returns story from provider', () async {
    final service = NativeToolExecutorService(
      launch: (_, __) async => true,
      storyProvider: (topic) async => '從前從前有一隻小狗…',
    );
    final result = await service.execute(
      intent: _intent('tell_story', arguments: {'topic': '小狗'}),
      reminderController: _FakeReminderController(),
      searchService: SearchService(),
      navigationController: AppNavigationController(),
      memoryController: _memoryController(),
    );

    expect(result.success, isTrue, reason: result.message);
    expect(result.message, contains('小狗'));
  });

  test('purchase_pet_skin without wiring returns honest shop message (no fake success)',
      () async {
    final service = NativeToolExecutorService(launch: (_, __) async => true);
    final result = await service.execute(
      intent: _intent('purchase_pet_skin',
          riskLevel: AgentToolRiskLevel.high, requiresConfirmation: true),
      reminderController: _FakeReminderController(),
      searchService: SearchService(),
      navigationController: AppNavigationController(),
      memoryController: _memoryController(),
    );

    expect(result.success, isFalse);
    expect(result.message, contains('商城'));
  });
}

AgentToolIntent _intent(
  String toolName, {
  AgentToolRiskLevel riskLevel = AgentToolRiskLevel.low,
  bool requiresConfirmation = false,
  Map<String, dynamic> arguments = const {},
}) {
  return AgentToolIntent(
    id: 'agent_tool_test',
    toolName: toolName,
    displayName: toolName,
    arguments: arguments,
    requiresConfirmation: requiresConfirmation,
    riskLevel: riskLevel,
    status: AgentToolStatus.pending,
    userFacingMessage: toolName,
    createdAt: DateTime.now(),
  );
}

MemoryController _memoryController() {
  SharedPreferences.setMockInitialValues({});
  return MemoryController(MemoryService());
}

class _ThrowingReminderController extends ReminderController {
  _ThrowingReminderController()
      : super(
          reminderService: ReminderService(),
          notificationService: NotificationService(),
        );

  @override
  Future<Reminder?> createFromVoice(String text) async {
    throw Exception('secret-stack-detail');
  }
}

class _SpyMemoryController extends MemoryController {
  _SpyMemoryController() : super(MemoryService());

  bool forgetCalled = false;

  @override
  Future<void> forgetRecentMemory() async {
    forgetCalled = true;
  }
}

class _FakeReminderController extends ReminderController {
  _FakeReminderController()
      : super(
          reminderService: ReminderService(),
          notificationService: NotificationService(),
        );

  String createdText = '';

  @override
  Future<Reminder?> createFromVoice(String text) async {
    createdText = text;
    return const Reminder(
      id: 'r1',
      title: '吃藥',
      hour: 20,
      minute: 0,
      repeatType: 'none',
      note: '',
      enabled: true,
    );
  }
}
