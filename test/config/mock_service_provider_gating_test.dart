import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pet_companion_app/config/app_config.dart';
import 'package:pet_companion_app/controllers/check_in_controller.dart';
import 'package:pet_companion_app/controllers/inventory_controller.dart';
import 'package:pet_companion_app/controllers/pet_stats_controller.dart';
import 'package:pet_companion_app/controllers/profile_controller.dart';
import 'package:pet_companion_app/controllers/reminder_controller.dart';
import 'package:pet_companion_app/controllers/task_controller.dart';
import 'package:pet_companion_app/controllers/wallet_controller.dart';
import 'package:pet_companion_app/services/ai_tool_router.dart';
import 'package:pet_companion_app/services/check_in_storage_service.dart';
import 'package:pet_companion_app/services/companion_chat_service.dart';
import 'package:pet_companion_app/services/companion_content_service.dart';
import 'package:pet_companion_app/services/inventory_storage_service.dart';
import 'package:pet_companion_app/services/local_storage_service.dart';
import 'package:pet_companion_app/services/mock_ai_service.dart';
import 'package:pet_companion_app/services/mock_speech_to_text_service.dart';
import 'package:pet_companion_app/services/notification_service.dart';
import 'package:pet_companion_app/services/openai_speech_to_text_service.dart';
import 'package:pet_companion_app/services/pet_stats_storage_service.dart';
import 'package:pet_companion_app/services/reminder_service.dart';
import 'package:pet_companion_app/services/shop_service.dart';
import 'package:pet_companion_app/services/speech_to_text_service.dart';
import 'package:pet_companion_app/services/web_search_service.dart';

/// CR-0049-C：驗證 MockAiService / MockSpeechToTextService 的 build-flavor 隔離。
///
/// `AppConfig.mockServicesEnabled` 為 compile-time（`--dart-define`）常數，本檔
/// 以該值分流，鏡像 `lib/app.dart` 的注入條件：
///   - mockAiService: mockServicesEnabled ? MockAiService() : null
///   - sttService:    mockServicesEnabled ? MockSpeechToTextService()
///                                         : OpenAiSpeechToTextService(...)
///
/// - 一般 `flutter test`（development，預設 ALLOW_MOCK_SERVICES=false）
///   → mockServicesEnabled=false → 不建構 mock，AiToolRouter.mockAiService==null，
///     STT 為正式 OpenAiSpeechToTextService。
/// - `--dart-define=ALLOW_MOCK_SERVICES=true`（dev/test）→ 注入 mock。
/// - `--dart-define=APP_ENV=production ...` → 強制 mockServicesEnabled=false
///   → production provider 樹零 mock 實例。

/// 鏡像 app.dart：依 mockServicesEnabled 條件注入 mockAiService。
AiToolRouter buildRouterAsAppWired({
  required ProfileController profile,
}) {
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
    mockAiService:
        AppConfig.mockServicesEnabled ? MockAiService() : null,
    companionContentService: CompanionContentService(webSearchService),
    companionChatService: CompanionChatService(),
    reminderController: ReminderController(
      reminderService: ReminderService(),
      notificationService: NotificationService(),
    ),
  );
}

/// 鏡像 app.dart：依 mockServicesEnabled 條件選用 STT 實作。
SpeechToTextService buildSttAsAppWired(ProfileController profile) {
  return AppConfig.mockServicesEnabled
      ? MockSpeechToTextService()
      : OpenAiSpeechToTextService(proxyUrl: profile.sttProxyUrl);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('CR-0049-C MockAiService / MockSpeechToTextService gating', () {
    test('production 一律不啟用 mock（mockServicesEnabled）', () {
      if (AppConfig.isProduction) {
        expect(AppConfig.mockServicesEnabled, isFalse);
      } else {
        expect(AppConfig.mockServicesEnabled, AppConfig.allowMockServices);
      }
    });

    test('AiToolRouter.mockAiService 僅在 mockServicesEnabled 時注入', () async {
      final profile = ProfileController(LocalStorageService());
      await profile.load();
      final router = buildRouterAsAppWired(profile: profile);

      if (AppConfig.mockServicesEnabled) {
        expect(router.mockAiService, isA<MockAiService>(),
            reason: 'dev/test 應保留聊天 mock 供降級路徑使用');
        expect(router.useMockChat, isTrue);
      } else {
        expect(router.mockAiService, isNull,
            reason: 'production provider 樹不得建構 MockAiService');
        expect(router.useMockChat, isFalse,
            reason: 'production 聊天走後端正式引擎');
      }
    });

    test('production 聊天走後端，不呼叫 mock（即使 mock 為 null 也不崩）', () async {
      if (AppConfig.mockServicesEnabled) return;
      final profile = ProfileController(LocalStorageService());
      await profile.load();
      final router = AiToolRouter(
        profileController: profile,
        taskController: TaskController(profile),
        walletController: WalletController(profile),
        checkInController: CheckInController(CheckInStorageService()),
        petStatsController: PetStatsController(PetStatsStorageService()),
        inventoryController: InventoryController(InventoryStorageService()),
        shopService: const ShopService(),
        webSearchService: WebSearchService(),
        mockAiService: null,
        companionContentService:
            CompanionContentService(WebSearchService()),
        companionChatService: _ThrowingChatService(),
        reminderController: ReminderController(
          reminderService: ReminderService(),
          notificationService: NotificationService(),
        ),
        useMockChat: false,
      );

      // 後端失敗時回陪伴式白話錯誤，而非崩在 null mock 或假裝成功。
      final result = await router.route('你好呀');
      expect(result.toolName, 'chat');
      expect(result.success, isFalse);
      expect(result.message.trim(), isNotEmpty);
      expect(result.message.contains('MOCK'), isFalse);
    });

    test('STT 實作：production 為正式 OpenAiSpeechToTextService', () async {
      final profile = ProfileController(LocalStorageService());
      await profile.load();
      final stt = buildSttAsAppWired(profile);

      if (AppConfig.mockServicesEnabled) {
        expect(stt, isA<MockSpeechToTextService>(),
            reason: 'dev/test 應保留 STT mock 供降級路徑使用');
      } else {
        expect(stt, isA<OpenAiSpeechToTextService>(),
            reason: 'production 必須走正式 STT proxy，不得用 mock');
        expect(stt, isNot(isA<MockSpeechToTextService>()));
      }
    });
  });
}

/// 後端聊天 stub：固定丟出 [CompanionChatException]，驗證 production 失敗白話路徑。
class _ThrowingChatService extends CompanionChatService {
  @override
  Future<String> reply({
    required String userText,
    String petName = '',
    String memoryContextSummary = '',
    String? languageHint,
    String? replyLanguage,
  }) async {
    throw const CompanionChatException(
      code: 'openai_unavailable',
      message: 'backend down',
    );
  }
}
