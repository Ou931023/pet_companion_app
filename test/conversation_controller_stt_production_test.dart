import 'dart:io';

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
import 'package:pet_companion_app/services/companion_chat_service.dart';
import 'package:pet_companion_app/services/companion_content_service.dart';
import 'package:pet_companion_app/services/companion_reply_strategy_service.dart';
import 'package:pet_companion_app/services/emotion_services.dart';
import 'package:pet_companion_app/services/inventory_storage_service.dart';
import 'package:pet_companion_app/services/language_routing_service.dart';
import 'package:pet_companion_app/services/local_storage_service.dart';
import 'package:pet_companion_app/services/memory_service.dart';
import 'package:pet_companion_app/services/mock_ai_service.dart';
import 'package:pet_companion_app/services/notification_service.dart';
import 'package:pet_companion_app/services/pet_stats_storage_service.dart';
import 'package:pet_companion_app/services/reminder_service.dart';
import 'package:pet_companion_app/services/search_service.dart';
import 'package:pet_companion_app/services/shop_service.dart';
import 'package:pet_companion_app/services/speech_to_text_service.dart';
import 'package:pet_companion_app/services/taigi_asr_service.dart';
import 'package:pet_companion_app/services/taigi_asr_strategy.dart';
import 'package:pet_companion_app/services/text_to_speech_service.dart';
import 'package:pet_companion_app/services/web_search_service.dart';

/// CR-0049-A：正式版 STT 失敗時，不可 fallback 到 mock、不可假裝成功，
/// 也不可出現「Mock STT」等工程字樣，只能顯示長者友善的白話訊息。
///
/// 預設測試環境（無 dart-define）`AppConfig.mockServicesEnabled` 為 false，
/// 等同正式版的 STT 失敗路徑，因此可直接驗證「不 fallback mock」行為。
/// dev / test 的 mock 備援需 `--dart-define=ALLOW_MOCK_SERVICES=true` 才啟用。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('STT 拋出例外時不切回 mock、不顯示工程字樣，給白話訊息', () async {
    final controller = _build(sttService: _ThrowingSttService());
    final profile = controller.profileController;
    await profile.setSttMode(SttMode.openAiProxy);

    await controller.onPressToTalkEnd();

    // 未 fallback 到 mock。
    expect(profile.sttMode, SttMode.openAiProxy);
    // 沒有工程字樣。
    expect(controller.latestReply.contains('Mock'), isFalse);
    expect(controller.latestReply.contains('STT'), isFalse);
    // 是長者聽得懂的白話。
    expect(controller.latestReply.isNotEmpty, isTrue);

    controller.dispose();
  });

  test('STT 回網路錯誤時不切回 mock、給白話訊息', () async {
    final controller = _build(sttService: _NetworkErrorSttService());
    final profile = controller.profileController;
    await profile.setSttMode(SttMode.openAiProxy);

    await controller.onPressToTalkEnd();

    expect(profile.sttMode, SttMode.openAiProxy);
    expect(controller.latestReply.contains('Mock'), isFalse);
    expect(controller.latestReply.contains('STT'), isFalse);
    expect(controller.latestReply.isNotEmpty, isTrue);

    controller.dispose();
  });
}

ConversationController _build({required SpeechToTextService sttService}) {
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
    companionChatService: CompanionChatService(),
    reminderController: ReminderController(
      reminderService: ReminderService(),
      notificationService: NotificationService(),
    ),
    useMockChat: true,
  );

  return ConversationController(
    profileController: profileController,
    petController: petController,
    toolRouter: toolRouter,
    ttsService: TextToSpeechService(),
    sttService: sttService,
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

/// 正式語音辨識服務在錄音停止階段拋例外（例如連線層出狀況）。
class _ThrowingSttService implements SpeechToTextService {
  @override
  Future<void> startRecording() async {}

  @override
  Future<File?> stopRecording() async => throw Exception('stop failed');

  @override
  Future<SttResult> transcribeAudio(File audioFile) async =>
      throw Exception('transcribe failed');

  @override
  Future<SttResult> retryTranscription(File audioFile) async =>
      throw Exception('retry failed');

  @override
  SttResult handleNoiseDetected() => const SttResult(
        success: false,
        transcript: '',
        errorType: SttErrorType.noiseDetected,
      );

  @override
  SttResult handleEmptyTranscript() => const SttResult(
        success: false,
        transcript: '',
        errorType: SttErrorType.emptyTranscript,
      );
}

/// 正式語音辨識服務回網路錯誤（後端代理無法連線）。
class _NetworkErrorSttService implements SpeechToTextService {
  @override
  Future<void> startRecording() async {}

  @override
  Future<File?> stopRecording() async => File('dummy.wav');

  @override
  Future<SttResult> transcribeAudio(File audioFile) async => const SttResult(
        success: false,
        transcript: '',
        errorType: SttErrorType.networkError,
        message: '連線好像不太穩，我這次沒辦法聽清楚你說的話。',
      );

  @override
  Future<SttResult> retryTranscription(File audioFile) async =>
      transcribeAudio(audioFile);

  @override
  SttResult handleNoiseDetected() => const SttResult(
        success: false,
        transcript: '',
        errorType: SttErrorType.noiseDetected,
      );

  @override
  SttResult handleEmptyTranscript() => const SttResult(
        success: false,
        transcript: '',
        errorType: SttErrorType.emptyTranscript,
      );
}
