import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
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
import 'package:pet_companion_app/controllers/voice_agent_controller.dart';
import 'package:pet_companion_app/controllers/wallet_controller.dart';
import 'package:pet_companion_app/models/conversation_turn.dart';
import 'package:pet_companion_app/models/source_reference.dart';
import 'package:pet_companion_app/onboarding/coach_mark_keys.dart';
import 'package:pet_companion_app/screens/home_screen.dart';
import 'package:pet_companion_app/screens/settings_screen.dart';
import 'package:pet_companion_app/services/ai_navigation_service.dart';
import 'package:pet_companion_app/services/ai_tool_router.dart';
import 'package:pet_companion_app/services/asr_strategy_service.dart';
import 'package:pet_companion_app/services/check_in_storage_service.dart';
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
import 'package:pet_companion_app/widgets/source_reference_list.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('HomeScreen does not overflow at small height', (tester) async {
    await binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => binding.setSurfaceSize(null));
    final harness = await _HomeHarness.create();
    addTearDown(harness.dispose);

    await _pumpHomeScreen(tester, harness);
  });

  testWidgets('HomeScreen handles long AI reply and sources without overflow',
      (tester) async {
    await binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => binding.setSurfaceSize(null));
    final harness = await _HomeHarness.create();
    addTearDown(harness.dispose);
    harness.conversationController.appendExternalTurn(
      ConversationTurn(
        timestamp: DateTime.now(),
        userText: '幫我查一下睡不好可以怎麼辦',
        petReply: List.filled(
          10,
          '我聽得出來你昨晚很辛苦，我先陪你慢慢把身體放鬆下來。',
        ).join(),
        toolName: 'verticalSearch',
        sources: const [
          SourceReference(
            title: '長者睡眠照護與日常放鬆建議',
            url: 'https://example.com/sleep',
            siteName: '健康資料站',
            summary: '整理睡前放鬆、白天活動與就醫觀察等方向。',
            publishedAt: '2026-05-19',
          ),
          SourceReference(
            title: '睡不好時可先觀察的生活習慣',
            url: 'https://example.com/rest',
            siteName: '照護資訊網',
            summary: '避免過晚咖啡因、固定作息，並記錄連續失眠情形。',
            publishedAt: '2026-05-18',
          ),
        ],
      ),
    );

    await _pumpHomeScreen(tester, harness);
  });

  testWidgets('每日簽到彈窗在小螢幕（320 寬）不 overflow，且顯示標題與簽到按鈕',
      (tester) async {
    await binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => binding.setSurfaceSize(null));
    final harness = await _HomeHarness.create();
    addTearDown(harness.dispose);
    // 產生本月獎勵表，讓格子顯示金幣 / 禮物（更貼近實機畫面）。
    await harness.checkInController.load();

    await tester.pumpWidget(_homeHost(harness));
    await tester.pump();

    // 點首頁的簽到月曆入口開啟彈窗（有界 pump，不用 pumpAndSettle 以免卡在寵物動畫）。
    await tester.tap(find.byTooltip('簽到月曆'));
    await tester.pump();
    // pump 滿 1 秒：完成彈窗開啟動畫，並觸發首頁寵物的 1 秒 rest→listen 計時器，
    // 避免測試結束時殘留 pending timer（沿用 _pumpHomeScreen 慣例）。
    await tester.pump(const Duration(seconds: 1));

    // 開啟過程若 overflow，widget test 會拋例外導致失敗。
    expect(tester.takeException(), isNull);
    expect(find.textContaining('每日簽到'), findsOneWidget);
    expect(find.text('今天簽到'), findsOneWidget);
    expect(find.byType(GridView), findsOneWidget);

    // 拆掉 widget 樹，取消 HomeScreen 的動畫 timer（沿用 _pumpHomeScreen 慣例）。
    await tester.pumpWidget(const SizedBox.shrink());
    harness.dispose();
  });

  testWidgets('HomeScreen hides ASR route and emotion fusion debug text',
      (tester) async {
    await binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => binding.setSurfaceSize(null));
    final harness = await _HomeHarness.create();
    addTearDown(harness.dispose);

    await tester.pumpWidget(_homeHost(harness));
    await tester.pump();

    expect(find.textContaining('ASR:'), findsNothing);
    expect(find.textContaining('lang:'), findsNothing);
    expect(find.textContaining('routeReason'), findsNothing);
    expect(find.textContaining('情緒推測'), findsNothing);
    expect(find.textContaining('pauseDensity'), findsNothing);
    expect(find.textContaining('speechRate'), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    harness.dispose();
  });

  testWidgets('HomeScreen hides search metadata line', (tester) async {
    await binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => binding.setSurfaceSize(null));
    final harness = await _HomeHarness.create();
    addTearDown(harness.dispose);
    harness.conversationController.appendExternalTurn(
      ConversationTurn(
        timestamp: DateTime.now(),
        userText: '查一下睡眠',
        petReply: '我找到兩個可以參考的方向。',
        toolName: 'verticalSearch',
        toolUsed: 'webSearch',
        searchMode: 'health',
        searchProvider: 'official_provider',
        sources: const [
          SourceReference(
            title: '睡眠照護建議',
            url: 'https://example.com/sleep',
            siteName: '健康資料站',
            summary: '睡前放鬆與作息建議。',
          ),
        ],
      ),
    );

    await tester.pumpWidget(_homeHost(harness));
    await tester.pump();

    expect(find.textContaining('mode:'), findsNothing);
    expect(find.textContaining('provider:'), findsNothing);
    expect(find.textContaining('toolUsed:'), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    harness.dispose();
  });

  testWidgets('SourceReferenceList shows at most two product sources',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SourceReferenceList(
            sources: [
              SourceReference(
                title: '來源一',
                url: 'https://example.com/one?score=0.9',
                siteName: '網站一',
                summary: '摘要一',
              ),
              SourceReference(
                title: '來源二',
                url: 'https://example.com/two',
                siteName: '網站二',
                summary: '摘要二',
              ),
              SourceReference(
                title: '來源三',
                url: 'https://example.com/three',
                siteName: '網站三',
                summary: '摘要三',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('來源一'), findsOneWidget);
    expect(find.text('來源二'), findsOneWidget);
    expect(find.text('來源三'), findsNothing);
    expect(find.textContaining('https://'), findsNothing);
    expect(find.textContaining('score'), findsNothing);
    expect(find.textContaining('rank'), findsNothing);
    expect(find.textContaining('provider'), findsNothing);
  });

  testWidgets('HomeScreen does not overflow with 1.3 text scale',
      (tester) async {
    await binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => binding.setSurfaceSize(null));
    final harness = await _HomeHarness.create();
    addTearDown(harness.dispose);
    harness.conversationController.showPetBubbleMessage(
      '我在這裡陪你，慢慢說就好。今天如果覺得心裡悶，我們可以先不用急著解決。',
    );

    await _pumpHomeScreen(tester, harness, textScale: 1.3);
  });

  testWidgets('SettingsScreen hides dev panels when SHOW_DEV_PANELS is off',
      (tester) async {
    final harness = await _HomeHarness.create();
    addTearDown(harness.dispose);

    await tester.pumpWidget(_settingsHost(harness));
    await tester.pumpAndSettle();

    // SHOW_DEV_PANELS 預設為 false：開發用面板不應出現在使用者設定頁。
    expect(tester.takeException(), isNull);
    expect(find.text('進階診斷（開發人員）'), findsNothing);
    expect(find.text('Realtime Diagnostics'), findsNothing);
    expect(find.text('Companion Debug Panel'), findsNothing);
    expect(find.text('AI Agent 工具測試'), findsNothing);
  });
}

Future<void> _pumpHomeScreen(
  WidgetTester tester,
  _HomeHarness harness, {
  double textScale = 1.0,
}) async {
  await tester.pumpWidget(_homeHost(harness, textScale: textScale));
  await tester.pump();
  expect(tester.takeException(), isNull);
  expect(find.byType(HomeScreen), findsOneWidget);

  await tester.pump(const Duration(seconds: 1));
  expect(tester.takeException(), isNull);

  await tester.pumpWidget(const SizedBox.shrink());
  harness.dispose();
}

Widget _homeHost(_HomeHarness harness, {double textScale = 1.0}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ProfileController>.value(
        value: harness.profileController,
      ),
      ChangeNotifierProvider<PetController>.value(
        value: harness.petController,
      ),
      ChangeNotifierProvider<PetStatsController>.value(
        value: harness.petStatsController,
      ),
      ChangeNotifierProvider<ConversationController>.value(
        value: harness.conversationController,
      ),
      ChangeNotifierProvider<VoiceAgentController>.value(
        value: harness.voiceAgentController,
      ),
      ChangeNotifierProvider<CheckInController>.value(
        value: harness.checkInController,
      ),
      ChangeNotifierProvider<WalletController>.value(
        value: harness.walletController,
      ),
      ChangeNotifierProvider<InventoryController>.value(
        value: harness.inventoryController,
      ),
      ChangeNotifierProvider<MemoryController>.value(
        value: harness.memoryController,
      ),
      ChangeNotifierProvider<AppNavigationController>.value(
        value: harness.navigationController,
      ),
      Provider<CoachMarkKeys>(create: (_) => CoachMarkKeys()),
    ],
    child: MaterialApp(
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const Scaffold(
        body: HomeScreen(),
      ),
    ),
  );
}

Widget _settingsHost(_HomeHarness harness) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ProfileController>.value(
        value: harness.profileController,
      ),
      ChangeNotifierProvider<PetController>.value(
        value: harness.petController,
      ),
      ChangeNotifierProvider<ConversationController>.value(
        value: harness.conversationController,
      ),
      ChangeNotifierProvider<VoiceAgentController>.value(
        value: harness.voiceAgentController,
      ),
      Provider<RealtimeVoiceService>.value(
        value: harness.realtimeVoiceService,
      ),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: SettingsScreen(),
      ),
    ),
  );
}

class _HomeHarness {
  _HomeHarness({
    required this.profileController,
    required this.petController,
    required this.petStatsController,
    required this.conversationController,
    required this.voiceAgentController,
    required this.checkInController,
    required this.walletController,
    required this.inventoryController,
    required this.taskController,
    required this.memoryController,
    required this.navigationController,
    required this.reminderController,
    required this.realtimeVoiceService,
  });

  final ProfileController profileController;
  final PetController petController;
  final PetStatsController petStatsController;
  final ConversationController conversationController;
  final VoiceAgentController voiceAgentController;
  final CheckInController checkInController;
  final WalletController walletController;
  final InventoryController inventoryController;
  final TaskController taskController;
  final MemoryController memoryController;
  final AppNavigationController navigationController;
  final ReminderController reminderController;
  final RealtimeVoiceService realtimeVoiceService;
  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    voiceAgentController.dispose();
    conversationController.dispose();
    taskController.dispose();
    memoryController.dispose();
    navigationController.dispose();
    reminderController.dispose();
    inventoryController.dispose();
    checkInController.dispose();
    walletController.dispose();
    petStatsController.dispose();
    petController.dispose();
    profileController.dispose();
  }

  static Future<_HomeHarness> create() async {
    SharedPreferences.setMockInitialValues({});
    final localStorage = LocalStorageService();
    final profileController = ProfileController(localStorage);
    await profileController.completeOnboarding('小伴');
    await profileController.setTtsEnabled(false);

    final petController = PetController();
    final petStatsController = PetStatsController(PetStatsStorageService());
    final checkInController = CheckInController(CheckInStorageService());
    final inventoryController = InventoryController(InventoryStorageService());
    final memoryController = MemoryController(MemoryService());
    final navigationController = AppNavigationController();
    final walletController = WalletController(profileController);
    final taskController = TaskController(profileController);
    final webSearchService = WebSearchService();
    final companionContentService = CompanionContentService(webSearchService);
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
    final reminderController = ReminderController(
      reminderService: ReminderService(),
      notificationService: NotificationService(),
    );
    final languageRoutingService = LanguageRoutingService(
      AsrStrategyService(
        strategies: const [
          OpenAiRealtimeAsrStrategy(),
          MockTaigiAsrStrategy(),
        ],
      ),
    );
    final conversationController = ConversationController(
      profileController: profileController,
      petController: petController,
      toolRouter: toolRouter,
      ttsService: TextToSpeechService(),
      mockSttService: MockSpeechToTextService(),
      storageService: localStorage,
      searchService: SearchService(),
      petStatsController: petStatsController,
      navigationService: const AiNavigationService(),
      navigationController: navigationController,
      reminderController: reminderController,
      emotionFusionService: const EmotionFusionService(),
      petEmotionMapper: const PetEmotionMapper(),
      memoryController: memoryController,
      companionReplyStrategy: const CompanionReplyStrategyService(),
      languageRoutingService: languageRoutingService,
      taigiAsrService: TaigiAsrService(),
    );
    final realtimeVoiceService = RealtimeVoiceService();
    final voiceAgentController = VoiceAgentController(
      profileController: profileController,
      petController: petController,
      petStatsController: petStatsController,
      conversationController: conversationController,
      realtimeVoiceService: realtimeVoiceService,
      companionEngineService: const CompanionEngineService(),
      languageRoutingService: languageRoutingService,
      memoryController: memoryController,
      navigationService: const AiNavigationService(),
      navigationController: navigationController,
    );

    return _HomeHarness(
      profileController: profileController,
      petController: petController,
      petStatsController: petStatsController,
      conversationController: conversationController,
      voiceAgentController: voiceAgentController,
      checkInController: checkInController,
      walletController: walletController,
      inventoryController: inventoryController,
      taskController: taskController,
      memoryController: memoryController,
      navigationController: navigationController,
      reminderController: reminderController,
      realtimeVoiceService: realtimeVoiceService,
    );
  }
}
