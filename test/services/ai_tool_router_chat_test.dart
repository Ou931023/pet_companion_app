import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/controllers/check_in_controller.dart';
import 'package:pet_companion_app/controllers/inventory_controller.dart';
import 'package:pet_companion_app/controllers/pet_stats_controller.dart';
import 'package:pet_companion_app/controllers/profile_controller.dart';
import 'package:pet_companion_app/controllers/reminder_controller.dart';
import 'package:pet_companion_app/controllers/task_controller.dart';
import 'package:pet_companion_app/controllers/wallet_controller.dart';
import 'package:pet_companion_app/services/check_in_storage_service.dart';
import 'package:pet_companion_app/services/companion_chat_service.dart';
import 'package:pet_companion_app/services/companion_content_service.dart';
import 'package:pet_companion_app/services/inventory_storage_service.dart';
import 'package:pet_companion_app/services/local_storage_service.dart';
import 'package:pet_companion_app/services/mock_ai_service.dart';
import 'package:pet_companion_app/services/notification_service.dart';
import 'package:pet_companion_app/services/pet_stats_storage_service.dart';
import 'package:pet_companion_app/services/reminder_service.dart';
import 'package:pet_companion_app/services/shop_service.dart';
import 'package:pet_companion_app/services/ai_tool_router.dart';
import 'package:pet_companion_app/services/web_search_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 後端聊天 stub：可回傳固定 reply，或丟出 [CompanionChatException]。
class _StubChatService extends CompanionChatService {
  _StubChatService({this.replyValue = 'BACKEND_REPLY', this.shouldThrow = false});

  final String replyValue;
  final bool shouldThrow;
  int callCount = 0;
  List<Map<String, String>> lastHistory = const [];

  @override
  Future<String> reply({
    required String userText,
    String petName = '',
    String memoryContextSummary = '',
    List<Map<String, String>> history = const [],
    String? languageHint,
    String? replyLanguage,
  }) async {
    callCount++;
    lastHistory = history;
    if (shouldThrow) {
      throw const CompanionChatException(
        code: 'openai_unavailable',
        message: 'backend down',
      );
    }
    return replyValue;
  }
}

/// 測試用通知服務：略過所有 local notification 平台呼叫（避免 plugin 在
/// 純 Dart 測試環境拋 LateInitializationError）。
class _FakeNotificationService extends NotificationService {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> scheduleReminder(reminder) async {}

  @override
  Future<void> cancelReminder(String id) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> rescheduleAll(reminders) async {}
}

/// Mock 聊天 spy：記錄是否被呼叫，回傳可辨識的哨兵字串。
class _SpyMockAiService extends MockAiService {
  bool called = false;

  @override
  String replyForChat(
    String text,
    String petName, {
    String memoryContextSummary = '',
  }) {
    called = true;
    return 'MOCK_REPLY';
  }
}

Future<AiToolRouter> _buildRouter({
  required bool useMockChat,
  CompanionChatService? chatService,
  MockAiService? mockAiService,
  ReminderController? reminderController,
}) async {
  final localStorage = LocalStorageService();
  final profile = ProfileController(localStorage);
  await profile.load();
  final webSearchService = WebSearchService();
  return AiToolRouter(
    profileController: profile,
    taskController: TaskController(profile),
    walletController: WalletController(profile),
    checkInController: CheckInController(CheckInStorageService()),
    petStatsController: PetStatsController(PetStatsStorageService()),
    inventoryController: InventoryController(InventoryStorageService()),
    shopService: const ShopService(),
    webSearchService: webSearchService,
    mockAiService: mockAiService ?? MockAiService(),
    companionContentService: CompanionContentService(webSearchService),
    companionChatService: chatService ?? _StubChatService(),
    reminderController: reminderController ??
        ReminderController(
          reminderService: ReminderService(),
          notificationService: NotificationService(),
        ),
    useMockChat: useMockChat,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'ttsEnabled': false});
  });

  group('AiToolRouter._chat production path (useMockChat=false)', () {
    test('純閒聊語句走 companionChatService，回後端 reply', () async {
      final chat = _StubChatService(replyValue: '我在這裡陪你呀。');
      final router = await _buildRouter(useMockChat: false, chatService: chat);

      final result = await router.route('你好呀');

      expect(result.toolName, 'chat');
      expect(result.success, isTrue);
      expect(result.shouldSpeak, isTrue);
      expect(result.message, '我在這裡陪你呀。');
      expect(chat.callCount, 1);
    });

    test('後端失敗時回陪伴式白話錯誤，不 fallback mock、不假成功', () async {
      final spyMock = _SpyMockAiService();
      final chat = _StubChatService(shouldThrow: true);
      final router = await _buildRouter(
        useMockChat: false,
        chatService: chat,
        mockAiService: spyMock,
      );

      final result = await router.route('你好呀');

      expect(result.toolName, 'chat');
      expect(result.success, isFalse);
      expect(result.shouldSpeak, isTrue);
      // 不可回 mock 罐頭、不可假成功。
      expect(result.message, isNot('MOCK_REPLY'));
      expect(result.message.trim(), isNotEmpty);
      expect(spyMock.called, isFalse);
      expect(chat.callCount, 1);
    });
  });

  group('AiToolRouter._chat dev/test path (useMockChat=true)', () {
    test('純閒聊語句走 mockAiService（既有行為）', () async {
      final spyMock = _SpyMockAiService();
      final chat = _StubChatService();
      final router = await _buildRouter(
        useMockChat: true,
        chatService: chat,
        mockAiService: spyMock,
      );

      final result = await router.route('你好呀');

      expect(result.toolName, 'chat');
      expect(result.success, isTrue);
      expect(result.message, 'MOCK_REPLY');
      expect(spyMock.called, isTrue);
      // 不可呼叫後端。
      expect(chat.callCount, 0);
    });
  });

  group('AiToolRouter reminder branch (B4)', () {
    test('建立提醒指令：實際建立提醒且 shouldSpeak == false', () async {
      final reminderController = ReminderController(
        reminderService: ReminderService(),
        notificationService: _FakeNotificationService(),
      );
      final router = await _buildRouter(
        useMockChat: false,
        reminderController: reminderController,
      );

      final result = await router.route('提醒我晚上八點吃藥');

      expect(result.toolName, 'createReminder');
      expect(result.success, isTrue);
      expect(result.shouldSpeak, isFalse);
      expect(reminderController.reminders, hasLength(1));
      expect(reminderController.reminders.first.title, '吃藥');
    });

    test('查詢提醒指令：shouldSpeak == false', () async {
      final reminderController = ReminderController(
        reminderService: ReminderService(),
        notificationService: _FakeNotificationService(),
      );
      final router = await _buildRouter(
        useMockChat: false,
        reminderController: reminderController,
      );

      final result = await router.route('我的提醒');

      expect(result.toolName, 'listReminders');
      expect(result.shouldSpeak, isFalse);
    });
  });
}
