import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pet_companion_app/controllers/app_navigation_controller.dart';
import 'package:pet_companion_app/controllers/care_alert_controller.dart';
import 'package:pet_companion_app/controllers/check_in_controller.dart';
import 'package:pet_companion_app/controllers/conversation_controller.dart';
import 'package:pet_companion_app/controllers/inventory_controller.dart';
import 'package:pet_companion_app/controllers/memory_controller.dart';
import 'package:pet_companion_app/controllers/pet_controller.dart';
import 'package:pet_companion_app/controllers/pet_stats_controller.dart';
import 'package:pet_companion_app/controllers/profile_controller.dart';
import 'package:pet_companion_app/controllers/reminder_controller.dart';
import 'package:pet_companion_app/controllers/task_controller.dart';
import 'package:pet_companion_app/controllers/voice_agent_controller.dart';
import 'package:pet_companion_app/controllers/wallet_controller.dart';
import 'package:pet_companion_app/models/care_alert.dart';
import 'package:pet_companion_app/models/companion_analysis_result.dart';
import 'package:pet_companion_app/services/ai_navigation_service.dart';
import 'package:pet_companion_app/services/ai_tool_router.dart';
import 'package:pet_companion_app/services/asr_strategy_service.dart';
import 'package:pet_companion_app/services/care_alert_storage_service.dart';
import 'package:pet_companion_app/services/check_in_storage_service.dart';
import 'package:pet_companion_app/services/companion_chat_service.dart';
import 'package:pet_companion_app/services/companion_content_service.dart';
import 'package:pet_companion_app/services/companion_engine_service.dart';
import 'package:pet_companion_app/services/companion_reply_strategy_service.dart';
import 'package:pet_companion_app/services/emotion_services.dart';
import 'package:pet_companion_app/services/inventory_storage_service.dart';
import 'package:pet_companion_app/services/language_routing_service.dart';
import 'package:pet_companion_app/services/local_storage_service.dart';
import 'package:pet_companion_app/services/memory_service.dart';
import 'package:pet_companion_app/services/mock_ai_service.dart';
import 'package:pet_companion_app/services/mock_speech_to_text_service.dart';
import 'package:pet_companion_app/services/notification_service.dart';
import 'package:pet_companion_app/services/pet_stats_storage_service.dart';
import 'package:pet_companion_app/services/realtime_voice_service.dart';
import 'package:pet_companion_app/services/reminder_service.dart';
import 'package:pet_companion_app/services/search_service.dart';
import 'package:pet_companion_app/services/shop_service.dart';
import 'package:pet_companion_app/services/taigi_asr_strategy.dart';
import 'package:pet_companion_app/services/taigi_asr_service.dart';
import 'package:pet_companion_app/services/text_to_speech_service.dart';
import 'package:pet_companion_app/services/web_search_service.dart';

// Care Alert companion-analysis hook 測試。
//
// 驗證 VoiceAgentController 在 companion 分析回傳 needsHumanSupport 時，
// 以旁路方式建立 CareAlert，且同一輪（同一 turnId）不重複建立。

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'ttsEnabled': false});
  });

  test('companion analysis with needsHumanSupport creates one care alert',
      () async {
    final careAlertController = CareAlertController(CareAlertStorageService());
    await careAlertController.loadAlerts();
    final harness = await _CareAlertHookHarness.create(
      companionEngineService:
          _FakeCompanionEngineService(needsHumanSupport: true),
      careAlertController: careAlertController,
    );

    await harness.controller.startRealtimeConversation();
    harness.realtimeService.handleDataChannelEventForTest('''
{"type":"conversation.item.input_audio_transcription.completed","transcript":"我覺得很孤單"}
''');
    await pumpEventQueue();
    await pumpEventQueue();

    expect(careAlertController.alerts.length, 1);
    final alert = careAlertController.alerts.first;
    expect(alert.riskLevel, CareAlertRiskLevel.urgent);
    expect(alert.source, 'companion_analysis');
    expect(alert.transcriptSnippet, '我覺得很孤單');
    expect(alert.isRead, isFalse);
    expect(alert.id, startsWith('care_alert_'));

    harness.dispose();
  });

  test('companion analysis without needsHumanSupport creates no care alert',
      () async {
    final careAlertController = CareAlertController(CareAlertStorageService());
    await careAlertController.loadAlerts();
    final harness = await _CareAlertHookHarness.create(
      companionEngineService:
          _FakeCompanionEngineService(needsHumanSupport: false),
      careAlertController: careAlertController,
    );

    await harness.controller.startRealtimeConversation();
    harness.realtimeService.handleDataChannelEventForTest('''
{"type":"conversation.item.input_audio_transcription.completed","transcript":"今天天氣很好"}
''');
    await pumpEventQueue();
    await pumpEventQueue();

    expect(careAlertController.alerts, isEmpty);

    harness.dispose();
  });

  test('a single turn (same turnId) does not create duplicate care alerts',
      () async {
    final careAlertController = CareAlertController(CareAlertStorageService());
    await careAlertController.loadAlerts();
    final harness = await _CareAlertHookHarness.create(
      companionEngineService:
          _FakeCompanionEngineService(needsHumanSupport: true),
      careAlertController: careAlertController,
    );

    await harness.controller.startRealtimeConversation();
    harness.realtimeService.handleDataChannelEventForTest('''
{"type":"conversation.item.input_audio_transcription.completed","transcript":"我頭很暈"}
''');
    // 反覆清空 event queue，確認同一輪不會重複建立。
    await pumpEventQueue();
    await pumpEventQueue();
    await pumpEventQueue();

    expect(careAlertController.alerts.length, 1);

    harness.dispose();
  });

  test('triggerSummary 優先採用 careAlertSummary（CR-0003 B3 wiring）', () async {
    final careAlertController = CareAlertController(CareAlertStorageService());
    await careAlertController.loadAlerts();
    final harness = await _CareAlertHookHarness.create(
      companionEngineService: _FakeCompanionEngineService(
        needsHumanSupport: true,
        careAlertSummary: '系統偵測長者提到睡眠不佳，建議照護人員主動關心近況。',
        implicitMeaning: '使用者需要陪伴。',
      ),
      careAlertController: careAlertController,
    );

    await harness.controller.startRealtimeConversation();
    harness.realtimeService.handleDataChannelEventForTest('''
{"type":"conversation.item.input_audio_transcription.completed","transcript":"我都睡不好"}
''');
    await pumpEventQueue();
    await pumpEventQueue();

    expect(careAlertController.alerts.length, 1);
    expect(
      careAlertController.alerts.first.triggerSummary,
      '系統偵測長者提到睡眠不佳，建議照護人員主動關心近況。',
    );

    harness.dispose();
  });

  test('careAlertSummary 缺失時 fallback 到 implicitMeaning（CR-0003 B3 wiring）',
      () async {
    final careAlertController = CareAlertController(CareAlertStorageService());
    await careAlertController.loadAlerts();
    final harness = await _CareAlertHookHarness.create(
      companionEngineService: _FakeCompanionEngineService(
        needsHumanSupport: true,
        careAlertSummary: '',
        implicitMeaning: '使用者可能感到孤單，需要被溫柔確認。',
      ),
      careAlertController: careAlertController,
    );

    await harness.controller.startRealtimeConversation();
    harness.realtimeService.handleDataChannelEventForTest('''
{"type":"conversation.item.input_audio_transcription.completed","transcript":"我覺得孤單"}
''');
    await pumpEventQueue();
    await pumpEventQueue();

    expect(careAlertController.alerts.length, 1);
    expect(
      careAlertController.alerts.first.triggerSummary,
      '使用者可能感到孤單，需要被溫柔確認。',
    );

    harness.dispose();
  });
}

RealtimeHealthStatus _healthyBackend() {
  return RealtimeHealthStatus(
    ok: true,
    hasOpenAiKey: true,
    realtimeModel: 'gpt-realtime',
    checkedAt: DateTime.now(),
  );
}

/// 測試用假的 companion engine：回傳可控的 safety 結果，並 echo turnId
/// （與真實後端行為一致，才能通過 VoiceAgentController 的 staleness guard）。
class _FakeCompanionEngineService extends CompanionEngineService {
  _FakeCompanionEngineService({
    required this.needsHumanSupport,
    this.careAlertSummary = '',
    this.implicitMeaning = '',
  }) : super();

  final bool needsHumanSupport;
  final String careAlertSummary;
  final String implicitMeaning;

  @override
  Future<CompanionAnalysisResult?> analyze({
    required String sttProxyUrl,
    required String userId,
    required String sessionId,
    required String turnId,
    required String petName,
    required String transcript,
    required Map<String, dynamic> petState,
    List<Map<String, dynamic>> recentTurns = const [],
    String languageHint = 'zh',
    Map<String, dynamic> audioFeatures = const {
      'volumeMean': null,
      'pauseDensity': null,
      'speechRate': null,
    },
  }) async {
    return CompanionAnalysisResult.fromJson({
      'turnId': turnId,
      'implicitMeaning': implicitMeaning,
      'careAlertSummary': careAlertSummary,
      'safety': {
        'riskLevel': 'urgent',
        'needsHumanSupport': needsHumanSupport,
      },
    });
  }
}

/// 自帶 harness：建構一個可驅動 Realtime 對話輪的 VoiceAgentController。
class _CareAlertHookHarness {
  _CareAlertHookHarness({
    required this.controller,
    required this.realtimeService,
    required this.petController,
    required this.conversationController,
  });

  final VoiceAgentController controller;
  final RealtimeVoiceService realtimeService;
  final PetController petController;
  final ConversationController conversationController;

  static Future<_CareAlertHookHarness> create({
    required CompanionEngineService companionEngineService,
    required CareAlertController careAlertController,
  }) async {
    final realtimeService = RealtimeVoiceService(
      healthCheckImplementationForTesting: (_) async => _healthyBackend(),
      connectImplementationForTesting: (_) async {},
    );
    final localStorage = LocalStorageService();
    final profile = ProfileController(localStorage);
    await profile.load();
    final petController = PetController();
    final petStats = PetStatsController(PetStatsStorageService());
    final memoryController = MemoryController(MemoryService());
    final navigationController = AppNavigationController();
    const navigationService = AiNavigationService();
    final webSearchService = WebSearchService();
    final reminderController = ReminderController(
      reminderService: ReminderService(),
      notificationService: NotificationService(),
    );
    final taskController = TaskController(profile);
    final walletController = WalletController(profile);
    final checkInController = CheckInController(CheckInStorageService());
    final inventoryController = InventoryController(InventoryStorageService());
    final companionContentService = CompanionContentService(webSearchService);
    final toolRouter = AiToolRouter(
      profileController: profile,
      taskController: taskController,
      walletController: walletController,
      checkInController: checkInController,
      petStatsController: petStats,
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
    final conversationController = ConversationController(
      profileController: profile,
      petController: petController,
      toolRouter: toolRouter,
      ttsService: TextToSpeechService(),
      sttService: MockSpeechToTextService(),
      storageService: localStorage,
      searchService: SearchService(),
      petStatsController: petStats,
      navigationService: navigationService,
      navigationController: navigationController,
      reminderController: reminderController,
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
    final controller = VoiceAgentController(
      profileController: profile,
      petController: petController,
      petStatsController: petStats,
      conversationController: conversationController,
      realtimeVoiceService: realtimeService,
      companionEngineService: companionEngineService,
      languageRoutingService: LanguageRoutingService(
        AsrStrategyService(
          strategies: const [
            OpenAiRealtimeAsrStrategy(),
            MockTaigiAsrStrategy(),
          ],
        ),
      ),
      memoryController: memoryController,
      navigationService: navigationService,
      navigationController: navigationController,
      careAlertController: careAlertController,
    );
    return _CareAlertHookHarness(
      controller: controller,
      realtimeService: realtimeService,
      petController: petController,
      conversationController: conversationController,
    );
  }

  void dispose() {
    controller.dispose();
    conversationController.dispose();
    petController.dispose();
  }
}
