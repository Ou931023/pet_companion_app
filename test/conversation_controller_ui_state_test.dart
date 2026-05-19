import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pet_companion_app/controllers/app_navigation_controller.dart';
import 'package:pet_companion_app/controllers/check_in_controller.dart';
import 'package:pet_companion_app/controllers/conversation_controller.dart';
import 'package:pet_companion_app/controllers/inventory_controller.dart';
import 'package:pet_companion_app/controllers/memory_controller.dart';
import 'package:pet_companion_app/controllers/pet_controller.dart';
import 'package:pet_companion_app/controllers/pet_stats_controller.dart';
import 'package:pet_companion_app/controllers/profile_controller.dart';
import 'package:pet_companion_app/controllers/reminder_controller.dart';
import 'package:pet_companion_app/controllers/task_controller.dart';
import 'package:pet_companion_app/controllers/wallet_controller.dart';
import 'package:pet_companion_app/services/ai_navigation_service.dart';
import 'package:pet_companion_app/services/ai_tool_router.dart';
import 'package:pet_companion_app/services/asr_strategy_service.dart';
import 'package:pet_companion_app/services/check_in_storage_service.dart';
import 'package:pet_companion_app/services/companion_content_service.dart';
import 'package:pet_companion_app/services/companion_reply_strategy_service.dart';
import 'package:pet_companion_app/services/emotion_services.dart';
import 'package:pet_companion_app/services/language_routing_service.dart';
import 'package:pet_companion_app/services/inventory_storage_service.dart';
import 'package:pet_companion_app/services/local_storage_service.dart';
import 'package:pet_companion_app/services/memory_service.dart';
import 'package:pet_companion_app/services/mock_ai_service.dart';
import 'package:pet_companion_app/services/mock_speech_to_text_service.dart';
import 'package:pet_companion_app/services/notification_service.dart';
import 'package:pet_companion_app/services/pet_stats_storage_service.dart';
import 'package:pet_companion_app/services/reminder_service.dart';
import 'package:pet_companion_app/services/search_service.dart';
import 'package:pet_companion_app/services/shop_service.dart';
import 'package:pet_companion_app/services/taigi_asr_strategy.dart';
import 'package:pet_companion_app/services/taigi_asr_service.dart';
import 'package:pet_companion_app/services/text_to_speech_service.dart';
import 'package:pet_companion_app/services/web_search_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConversationController temporary user UI state', () {
    late ConversationController controller;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      controller = _createConversationController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('draft bubble updates while typing', () {
      controller.updateDraftText(' 我想聊聊天 ');

      expect(controller.currentDraftText, '我想聊聊天');
      expect(controller.temporaryUserBubbleText, '我想聊聊天');
      expect(controller.temporaryUserBubbleStatus, '輸入中');
    });

    test('speech partial takes precedence over draft bubble', () {
      controller.updateDraftText('文字草稿');
      controller.updateRealtimePartialTranscript('語音 partial');

      expect(controller.currentDraftText, '文字草稿');
      expect(controller.temporaryUserBubbleText, '語音 partial');
      expect(controller.temporaryUserBubbleStatus, '聆聽中');
    });

    test('completed transcript clears temporary state and shows formal text',
        () {
      controller.updateRealtimePartialTranscript('今天家裡');
      controller.commitRealtimeFinalTranscript(' 今天家裡好安靜 ');

      expect(controller.currentPartialTranscript, isEmpty);
      expect(controller.isUserSpeaking, isFalse);
      expect(controller.isAwaitingFinalTranscript, isFalse);
      expect(controller.temporaryUserBubbleText, isEmpty);
      expect(controller.latestUserText, '今天家裡好安靜');
    });

    test('empty completed transcript clears temporary state only', () {
      controller.updateRealtimePartialTranscript('今天家裡');
      controller.commitRealtimeFinalTranscript('   ');

      expect(controller.currentPartialTranscript, isEmpty);
      expect(controller.latestUserText, isEmpty);
      expect(controller.temporaryUserBubbleText, isEmpty);
    });

    test('text input stores Taigi language context in history', () async {
      await controller.profileController.setTtsEnabled(false);

      await controller.quickAction('今仔日家裡攏無人，我感覺足孤單');

      expect(controller.history.first.userText, contains('今仔日'));
      expect(controller.history.first.languageHint, 'taigi');
      expect(controller.history.first.routeReason, 'taigi_mixed_zh_detected');
      expect(controller.history.first.asrSource, 'text_input');
      expect(controller.history.first.replyLanguage, 'mixed-zh-taigi');
      expect(controller.history.first.emotionTag, isNot('neutral'));
    });

    test('plain Mandarin text input remains zh context', () async {
      await controller.profileController.setTtsEnabled(false);

      await controller.quickAction('我今天想去買東西');

      expect(controller.history.first.languageHint, 'zh');
      expect(controller.history.first.routeReason, 'zh_text_default');
      expect(controller.history.first.replyLanguage, 'zh-TW');
    });

    test('empty Taigi ASR transcript does not add a conversation turn',
        () async {
      await controller.profileController.setTtsEnabled(false);

      await controller.handleTaigiAsrTranscript('   ');

      expect(controller.history, isEmpty);
    });

    test('Taigi ASR transcript stores source and route metadata', () async {
      await controller.profileController.setTtsEnabled(false);

      await controller.handleTaigiAsrTranscript('今仔日心情無好');

      expect(controller.history.first.userText, '今仔日心情無好');
      expect(controller.history.first.languageHint, 'taigi');
      expect(controller.history.first.asrSource, 'taigi-asr');
      expect(controller.history.first.routeReason, 'taigi_asr_transcript');
      expect(controller.history.first.replyLanguage, 'mixed-zh-taigi');
    });
  });
}

ConversationController _createConversationController() {
  final localStorage = LocalStorageService();
  final profileController = ProfileController(localStorage);
  final petController = PetController();
  final petStatsController = PetStatsController(PetStatsStorageService());
  final taskController = TaskController(profileController);
  final walletController = WalletController(profileController);
  final checkInController = CheckInController(CheckInStorageService());
  final inventoryController = InventoryController(InventoryStorageService());
  final webSearchService = WebSearchService();
  final companionContentService = CompanionContentService(webSearchService);
  final memoryController = MemoryController(MemoryService());
  final toolRouter = AiToolRouter(
    profileController: profileController,
    taskController: taskController,
    walletController: walletController,
    checkInController: checkInController,
    petStatsController: petStatsController,
    inventoryController: inventoryController,
    shopService: const ShopService(),
    webSearchService: webSearchService,
    mockAiService: MockAiService(),
    companionContentService: companionContentService,
  );

  return ConversationController(
    profileController: profileController,
    petController: petController,
    toolRouter: toolRouter,
    ttsService: TextToSpeechService(),
    mockSttService: MockSpeechToTextService(),
    storageService: localStorage,
    searchService: SearchService(),
    petStatsController: petStatsController,
    navigationService: const AiNavigationService(),
    navigationController: AppNavigationController(),
    reminderController: ReminderController(
      reminderService: ReminderService(),
      notificationService: NotificationService(),
    ),
    emotionFusionService: const EmotionFusionService(),
    petEmotionMapper: const PetEmotionMapper(),
    memoryController: memoryController,
    companionReplyStrategy: const CompanionReplyStrategyService(),
    languageRoutingService: LanguageRoutingService(
      AsrStrategyService(
        strategies: const [
          OpenAiRealtimeAsrStrategy(),
          MockTaigiAsrStrategy(),
        ],
      ),
    ),
    taigiAsrService: TaigiAsrService(),
  );
}
