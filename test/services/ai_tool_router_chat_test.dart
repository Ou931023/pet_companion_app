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
import 'package:pet_companion_app/services/app_usage_tracking_service.dart';
import 'package:pet_companion_app/services/web_search_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 後端聊天 stub：可回傳固定 reply，或丟出 [CompanionChatException]。
class _StubChatService extends CompanionChatService {
  _StubChatService(
      {this.replyValue = 'BACKEND_REPLY', this.shouldThrow = false});

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

class _RecordedUsageEvent {
  const _RecordedUsageEvent(this.eventType, this.metadata);

  final String eventType;
  final Map<String, Object?> metadata;
}

class _RecordingUsageTrackingService extends AppUsageTrackingService {
  final List<_RecordedUsageEvent> events = [];

  @override
  Future<bool> track(
    String eventType, {
    String? sessionId,
    int? durationMs,
    Map<String, Object?> metadata = const {},
  }) async {
    events.add(_RecordedUsageEvent(eventType, metadata));
    return true;
  }
}

Future<AiToolRouter> _buildRouter({
  required bool useMockChat,
  CompanionChatService? chatService,
  MockAiService? mockAiService,
  ReminderController? reminderController,
  AppUsageTrackingService? trackingService,
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
    trackingService: trackingService,
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

  group('AiToolRouter capability help', () {
    test('長者問可以說什麼時，本地回覆簡短可用範例，不呼叫後端', () async {
      final chat = _StubChatService(replyValue: 'BACKEND_REPLY');
      final router = await _buildRouter(useMockChat: false, chatService: chat);

      final result = await router.route('我可以說什麼');

      expect(result.toolName, 'capabilityHelp');
      expect(result.success, isTrue);
      expect(result.shouldSpeak, isTrue);
      expect(result.message, contains('提醒我晚上八點吃藥'));
      expect(result.message, contains('我今天心情不好'));
      expect(result.message, contains('地方新聞'));
      expect(chat.callCount, 0);
      expect(router.shouldHandleLocally('我可以說什麼'), isTrue);
    });

    test('台語口吻問能力時，也能被辨識', () async {
      final chat = _StubChatService(replyValue: 'BACKEND_REPLY');
      final router = await _buildRouter(useMockChat: false, chatService: chat);

      final result = await router.route('你會做啥物');

      expect(result.toolName, 'capabilityHelp');
      expect(result.shouldSpeak, isTrue);
      expect(chat.callCount, 0);
    });
  });

  group('AiToolRouter reminder branch (B4)', () {
    test('建立提醒指令：實際建立提醒且語音回報真實結果', () async {
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
      expect(result.shouldSpeak, isTrue);
      expect(result.message, contains('晚上8點'));
      expect(result.message, contains('吃藥'));
      expect(reminderController.reminders, hasLength(1));
      expect(reminderController.reminders.first.title, '吃藥');
    });

    test('查詢提醒指令：語音回報真實提醒清單', () async {
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
      expect(result.shouldSpeak, isTrue);
      expect(result.message, contains('目前還沒有提醒'));
    });

    test('模糊提醒指令：不建立提醒，會用語音追問時間', () async {
      final reminderController = ReminderController(
        reminderService: ReminderService(),
        notificationService: _FakeNotificationService(),
      );
      final router = await _buildRouter(
        useMockChat: false,
        reminderController: reminderController,
      );

      final result = await router.route('提醒我吃藥');

      expect(result.toolName, 'createReminder');
      expect(result.success, isFalse);
      expect(result.shouldSpeak, isTrue);
      expect(result.message, contains('什麼時候'));
      expect(result.message, contains('提醒我晚上八點吃藥'));
      expect(reminderController.reminders, isEmpty);
    });

    test('口語提醒變體：叫我 / 幫我記得 也會建立提醒', () async {
      final reminderController = ReminderController(
        reminderService: ReminderService(),
        notificationService: _FakeNotificationService(),
      );
      final router = await _buildRouter(
        useMockChat: false,
        reminderController: reminderController,
      );

      final first = await router.route('晚上八點叫我吃藥');
      final second = await router.route('幫我記得明天九點喝水');

      expect(first.toolName, 'createReminder');
      expect(first.success, isTrue);
      expect(second.toolName, 'createReminder');
      expect(second.success, isTrue);
      expect(reminderController.reminders, hasLength(2));
      expect(reminderController.reminders.map((r) => r.title), contains('吃藥'));
      expect(reminderController.reminders.map((r) => r.title), contains('喝水'));
    });
  });

  group('AiToolRouter settings tracking', () {
    test('語音調大文字會更新設定並上報 font_size_changed', () async {
      final tracking = _RecordingUsageTrackingService();
      final router = await _buildRouter(
        useMockChat: false,
        trackingService: tracking,
      );

      final result = await router.route('文字調大');

      expect(result.toolName, 'changeSettings');
      expect(result.success, isTrue);
      expect(result.shouldSpeak, isTrue);
      expect(tracking.events, hasLength(1));
      expect(tracking.events.first.eventType, 'font_size_changed');
      expect(tracking.events.first.metadata['setting'], 'font_scale');
      expect(tracking.events.first.metadata['source'], 'ai_tool_router');
    });

    test('語音改成慢慢說會上報 settings_changed', () async {
      final tracking = _RecordingUsageTrackingService();
      final router = await _buildRouter(
        useMockChat: false,
        trackingService: tracking,
      );

      final result = await router.route('說話慢一點');

      expect(result.toolName, 'changeSettings');
      expect(result.success, isTrue);
      expect(tracking.events, hasLength(1));
      expect(tracking.events.first.eventType, 'settings_changed');
      expect(tracking.events.first.metadata['setting'], 'speech_style');
      expect(tracking.events.first.metadata['value'], 'calm');
    });
  });

  group('AiToolRouter daily task voice completion', () {
    test('自然說「我吃飯了」會完成吃飯任務並語音回報', () async {
      final router = await _buildRouter(useMockChat: false);

      final result = await router.route('我吃飯了');

      expect(result.toolName, 'completeCareTask');
      expect(result.success, isTrue);
      expect(result.shouldSpeak, isTrue);
      expect(result.message, contains('吃飯任務'));
      expect(result.message, contains('金幣'));
    });

    test('台語口吻「食飽」也能完成吃飯任務', () async {
      final router = await _buildRouter(useMockChat: false);

      final result = await router.route('我食飽矣');

      expect(result.toolName, 'completeCareTask');
      expect(result.success, isTrue);
      expect(result.message, contains('吃飯任務'));
    });

    test('全部任務做完只完成低風險自我回報任務', () async {
      final router = await _buildRouter(useMockChat: false);

      final result = await router.route('我今天任務都做完了');

      expect(result.toolName, 'completeCareTask');
      expect(result.success, isTrue);
      expect(result.message, contains('喝水任務'));
      expect(result.message, contains('吃飯任務'));
      expect(result.message, contains('心情回報'));
      expect(result.message, contains('休息提醒'));
      expect(result.message, isNot(contains('每日簽到')));
    });

    test('吃藥完成不在遊戲化任務誤判，保留給今日任務照片驗證流程', () async {
      final chat = _StubChatService(replyValue: '我陪你一起去今日任務確認。');
      final router = await _buildRouter(useMockChat: false, chatService: chat);

      final result = await router.route('我吃藥了');

      expect(result.toolName, 'chat');
      expect(router.shouldHandleLocally('我吃藥了'), isFalse);
      expect(result.message, '我陪你一起去今日任務確認。');
    });
  });
}
