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
