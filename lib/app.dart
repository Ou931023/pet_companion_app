import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'config/app_config.dart';
import 'onboarding/coach_mark_controller.dart';
import 'onboarding/coach_mark_keys.dart';
import 'onboarding/coach_mark_overlay.dart';
import 'controllers/app_navigation_controller.dart';
import 'controllers/agent_tool_controller.dart';
import 'controllers/auth_controller.dart';
import 'controllers/care_alert_controller.dart';
import 'controllers/cart_controller.dart';
import 'controllers/consent_controller.dart';
import 'controllers/conversation_controller.dart';
import 'controllers/check_in_controller.dart';
import 'controllers/marketplace_controller.dart';
import 'controllers/inventory_controller.dart';
import 'controllers/memory_controller.dart';
import 'controllers/pet_controller.dart';
import 'controllers/pet_stats_controller.dart';
import 'controllers/profile_controller.dart';
import 'controllers/daily_care_task_controller.dart';
import 'controllers/reminder_controller.dart';
import 'controllers/task_controller.dart';
import 'controllers/voice_agent_controller.dart';
import 'controllers/wallet_controller.dart';
import 'routes/app_routes.dart';
import 'theme/app_theme.dart';
import 'utils/platform_liquid_glass.dart';
import 'screens/album_screen.dart';
import 'screens/care_alert_screen.dart';
import 'screens/consent_screen.dart';
import 'screens/conversation_detail_screen.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/marketplace/marketplace_screen.dart';
import 'screens/memory_management_screen.dart';
import 'screens/notification_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/puzzle_game_screen.dart';
import 'screens/register_screen.dart';
import 'screens/daily_care_task_screen.dart';
import 'screens/reminder_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/shop_screen.dart';
import 'services/ai_tool_router.dart';
import 'services/agent_router_service.dart';
import 'services/auth/auth_service.dart';
import 'services/ai_navigation_service.dart';
import 'services/asr_strategy_service.dart';
import 'services/care_alert_notification_service.dart';
import 'services/care_alert_storage_service.dart';
import 'services/check_in_storage_service.dart';
import 'services/companion_chat_service.dart';
import 'services/companion_content_service.dart';
import 'services/companion_engine_service.dart';
import 'services/contact_lookup_service.dart';
import 'models/care_alert.dart';
import 'services/companion_reply_strategy_service.dart';
import 'services/emotion_services.dart';
import 'services/inventory_storage_service.dart';
import 'services/local_storage_service.dart';
import 'services/language_routing_service.dart';
import 'services/marketplace_service.dart';
import 'services/memory_service.dart';
import 'services/mock_ai_service.dart';
import 'services/mock_shop_service.dart';
import 'services/mock_speech_to_text_service.dart';
import 'services/native_tool_executor_service.dart';
import 'services/notification_service.dart';
import 'services/openai_speech_to_text_service.dart';
import 'services/pet_stats_storage_service.dart';
import 'services/realtime_voice_service.dart';
import 'services/reminder_service.dart';
import 'services/search_service.dart';
import 'services/shop_service.dart';
import 'services/taigi_asr_strategy.dart';
import 'services/taigi_asr_service.dart';
import 'services/text_to_speech_service.dart';
import 'services/web_search_service.dart';

class PetCompanionApp extends StatelessWidget {
  const PetCompanionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider(create: (_) => LocalStorageService()),
        Provider(create: (_) => PetStatsStorageService()),
        Provider(create: (_) => CheckInStorageService()),
        Provider(create: (_) => InventoryStorageService()),
        Provider(create: (_) => CareAlertStorageService()),
        Provider(create: (_) => const ShopService()),
        // CR-0032 長照商品商城：商品服務 + 商品 / 購物車狀態。
        Provider(create: (_) => MarketplaceService()),
        ChangeNotifierProvider(
          create: (context) =>
              MarketplaceController(context.read<MarketplaceService>()),
        ),
        ChangeNotifierProvider(create: (_) => CartController()),
        Provider(create: (_) => MemoryService()),
        Provider(create: (_) => const CompanionEngineService()),
        Provider(create: (_) => const CompanionReplyStrategyService()),
        Provider(create: (_) => const AiNavigationService()),
        Provider(create: (_) => ReminderService()),
        Provider(create: (_) => NotificationService()),
        Provider(create: (_) => const EmotionFusionService()),
        Provider(create: (_) => const PetEmotionMapper()),
        Provider(create: (_) => AgentRouterService()),
        Provider(create: (_) => CoachMarkKeys()),
        ChangeNotifierProvider(create: (_) => CoachMarkController()),
        ChangeNotifierProvider(create: (_) => AppNavigationController()),
        // 知情同意 gate：純前端、只存本機，啟動時於 AppRoot 載入。
        ChangeNotifierProvider(create: (_) => ConsentController()),
        ChangeNotifierProvider(
          create: (_) => AuthController(authService: AuthService()),
        ),
        // CR-0045 B3：Care Alert 通知服務需帶 Authorization: Bearer <idToken>，
        // 由 AuthController 提供 token（firebase→新 idToken / mock→mock-id-token-<uid>）。
        // 置於 AuthController 之後，注入的 closure 於 notify() 時才讀取 AuthController。
        Provider(
          create: (context) => CareAlertNotificationService(
            authTokenProvider: () =>
                context.read<AuthController>().resolveNotifyAuthToken(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) =>
              ProfileController(context.read<LocalStorageService>()),
        ),
        ChangeNotifierProvider(
          create: (context) =>
              PetStatsController(context.read<PetStatsStorageService>()),
        ),
        ChangeNotifierProvider(
          create: (context) =>
              CheckInController(context.read<CheckInStorageService>()),
        ),
        ChangeNotifierProvider(
          create: (context) =>
              InventoryController(context.read<InventoryStorageService>()),
        ),
        ChangeNotifierProvider(
          create: (context) =>
              CareAlertController(context.read<CareAlertStorageService>()),
        ),
        ChangeNotifierProvider(
          create: (context) => MemoryController(context.read<MemoryService>()),
        ),
        ChangeNotifierProvider(
          create: (context) => ReminderController(
            reminderService: context.read<ReminderService>(),
            notificationService: context.read<NotificationService>(),
          ),
        ),
        // CR-0025 日常照護任務（與遊戲化 CareTask 不同功能）。
        ChangeNotifierProvider(create: (_) => DailyCareTaskController()),
        ChangeNotifierProxyProvider<ProfileController, TaskController>(
          create: (context) =>
              TaskController(context.read<ProfileController>()),
          update: (_, profile, taskController) =>
              taskController ?? TaskController(profile),
        ),
        ChangeNotifierProxyProvider<ProfileController, WalletController>(
          create: (context) =>
              WalletController(context.read<ProfileController>()),
          update: (_, profile, walletController) =>
              walletController ?? WalletController(profile),
        ),
        ChangeNotifierProvider(
          create: (context) => PetController(
            storageService: context.read<LocalStorageService>(),
          ),
        ),
        // CR-0034：mock service 注入依環境決定。production（或未開
        // ALLOW_MOCK_SERVICES）一律不注入未使用的 mock shop，確保正式版只走
        // 正式商城路徑。mock service 類別本身保留，供 dev / test 使用。
        if (AppConfig.mockServicesEnabled)
          Provider(create: (_) => MockShopService()),
        Provider(create: (_) => WebSearchService()),
        ProxyProvider<WebSearchService, CompanionContentService>(
          update: (_, webSearch, __) => CompanionContentService(webSearch),
        ),
        // CR-0049 B2/B3：陪伴聊天服務（按住說話的文字降級路徑），由 AiToolRouter
        // 視 useMockChat（預設 AppConfig.mockServicesEnabled）決定是否啟用。
        Provider(create: (_) => CompanionChatService()),
        // CR-0034：以下兩個 mock 是 AiToolRouter / ConversationController 建構子
        // 的結構性後援依賴（按住說話的降級路徑），故維持注入；正式版主要互動走
        // Realtime 語音與正式 STT proxy，不以 mock 作為正式資料來源。後援文案中的
        // 「Mock」工程字樣移除屬 CR-0039 範圍，本批不動。
        Provider(create: (_) => MockAiService()),
        Provider(create: (_) => MockSpeechToTextService()),
        Provider(create: (_) => SearchService()),
        Provider(create: (_) => TextToSpeechService()),
        Provider(create: (_) => TaigiAsrService()),
        Provider(create: (_) => RealtimeVoiceService()),
        // CR-0048：MockTaigiAsrStrategy 僅於 dev / test（mockServicesEnabled）
        // 納入 ASR strategy 清單；production 只保留正式的 OpenAiRealtimeAsrStrategy。
        // AsrStrategyService.strategyFor / LanguageRoutingService 對缺席的台語
        // strategy 已有 graceful fallback（回 OpenAI Realtime），故正式版不注入
        // 此 mock 不影響語音路由。MockAiService / MockSpeechToTextService 仍為
        // production runtime live 依賴，隔離移交 CR-0049，本案不動（見 line 189-190）。
        Provider(
          create: (_) => AsrStrategyService(
            strategies: [
              const OpenAiRealtimeAsrStrategy(),
              if (AppConfig.mockServicesEnabled) const MockTaigiAsrStrategy(),
            ],
          ),
        ),
        ProxyProvider<AsrStrategyService, LanguageRoutingService>(
          update: (_, strategies, __) => LanguageRoutingService(strategies),
        ),
        Provider<AiToolRouter>(
          create: (context) => AiToolRouter(
            profileController: context.read<ProfileController>(),
            taskController: context.read<TaskController>(),
            walletController: context.read<WalletController>(),
            checkInController: context.read<CheckInController>(),
            petStatsController: context.read<PetStatsController>(),
            inventoryController: context.read<InventoryController>(),
            shopService: context.read<ShopService>(),
            webSearchService: context.read<WebSearchService>(),
            mockAiService: context.read<MockAiService>(),
            companionContentService: context.read<CompanionContentService>(),
            companionChatService: context.read<CompanionChatService>(),
            reminderController: context.read<ReminderController>(),
          ),
        ),
        // Native Tool 執行層：放在所需控制器之後建立，讓高影響工具能沿用既有真實流程
        // （登出 / Care Alert 通知 / 說故事內容），不另開新架構、不加 demo-only 假成功。
        // 這些 callback 對應的工具皆 requiresConfirmation=true，只有使用者確認後才被呼叫。
        Provider<NativeToolExecutorService>(
          create: (context) => NativeToolExecutorService(
            contactLookup:
                ContactLookupService(context.read<ProfileController>()),
            onLogout: () => context.read<AuthController>().logout(),
            onNotifyCaregiver: ({required reason, required riskLevel}) async {
              // 先同步取出所需服務，避免 await 後再用 context。
              final careAlertController = context.read<CareAlertController>();
              final notifyService =
                  context.read<CareAlertNotificationService>();
              final sttProxyUrl =
                  context.read<ProfileController>().sttProxyUrl;
              final alert = CareAlert(
                id: 'agent_notify_${DateTime.now().microsecondsSinceEpoch}',
                createdAt: DateTime.now(),
                riskLevel: CareAlertRiskLevel.fromJson(riskLevel),
                category: CareAlertCategory.other,
                triggerSummary: reason,
                transcriptSnippet: reason,
                source: 'agent_tool',
                isRead: false,
              );
              await careAlertController.addAlert(alert);
              await notifyService.notify(
                sttProxyUrl: sttProxyUrl,
                alert: alert,
              );
              return true;
            },
            storyProvider: (topic) async {
              final result =
                  await context.read<CompanionContentService>().createContent(
                userText: topic.isEmpty ? '說個故事' : '說一個關於$topic的故事',
                preferences: const ['story'],
              );
              return result.message;
            },
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => AgentToolController(
            profileController: context.read<ProfileController>(),
            routerService: context.read<AgentRouterService>(),
            executorService: context.read<NativeToolExecutorService>(),
            reminderController: context.read<ReminderController>(),
            searchService: context.read<SearchService>(),
            navigationController: context.read<AppNavigationController>(),
            memoryController: context.read<MemoryController>(),
          ),
        ),
        ChangeNotifierProxyProvider6<
            ProfileController,
            PetController,
            AiToolRouter,
            TextToSpeechService,
            MockSpeechToTextService,
            SearchService,
            ConversationController>(
          create: (context) => ConversationController(
            profileController: context.read<ProfileController>(),
            petController: context.read<PetController>(),
            toolRouter: context.read<AiToolRouter>(),
            ttsService: context.read<TextToSpeechService>(),
            // 正式版注入正式語音辨識（OpenAI proxy，金鑰留在後端，Flutter 不放 key）；
            // dev / test（mockServicesEnabled）才注入 mock。
            sttService: AppConfig.mockServicesEnabled
                ? context.read<MockSpeechToTextService>()
                : OpenAiSpeechToTextService(
                    proxyUrl: context.read<ProfileController>().sttProxyUrl,
                  ),
            storageService: context.read<LocalStorageService>(),
            searchService: context.read<SearchService>(),
            petStatsController: context.read<PetStatsController>(),
            navigationService: context.read<AiNavigationService>(),
            navigationController: context.read<AppNavigationController>(),
            reminderController: context.read<ReminderController>(),
            emotionFusionService: context.read<EmotionFusionService>(),
            petEmotionMapper: context.read<PetEmotionMapper>(),
            memoryController: context.read<MemoryController>(),
            companionReplyStrategy:
                context.read<CompanionReplyStrategyService>(),
            languageRoutingService: context.read<LanguageRoutingService>(),
            taigiAsrService: context.read<TaigiAsrService>(),
          ),
          update: (context, profile, pet, router, tts, mockStt, search,
                  controller) =>
              controller ??
              ConversationController(
                profileController: profile,
                petController: pet,
                toolRouter: router,
                ttsService: tts,
                sttService: AppConfig.mockServicesEnabled
                    ? mockStt
                    : OpenAiSpeechToTextService(
                        proxyUrl: profile.sttProxyUrl,
                      ),
                storageService: context.read<LocalStorageService>(),
                searchService: search,
                petStatsController: context.read<PetStatsController>(),
                navigationService: context.read<AiNavigationService>(),
                navigationController: context.read<AppNavigationController>(),
                reminderController: context.read<ReminderController>(),
                emotionFusionService: context.read<EmotionFusionService>(),
                petEmotionMapper: context.read<PetEmotionMapper>(),
                memoryController: context.read<MemoryController>(),
                companionReplyStrategy:
                    context.read<CompanionReplyStrategyService>(),
                languageRoutingService: context.read<LanguageRoutingService>(),
                taigiAsrService: context.read<TaigiAsrService>(),
              ),
        ),
        ChangeNotifierProxyProvider6<
            ProfileController,
            PetController,
            PetStatsController,
            ConversationController,
            RealtimeVoiceService,
            AppNavigationController,
            VoiceAgentController>(
          create: (context) => VoiceAgentController(
            profileController: context.read<ProfileController>(),
            petController: context.read<PetController>(),
            petStatsController: context.read<PetStatsController>(),
            conversationController: context.read<ConversationController>(),
            realtimeVoiceService: context.read<RealtimeVoiceService>(),
            companionEngineService: context.read<CompanionEngineService>(),
            languageRoutingService: context.read<LanguageRoutingService>(),
            memoryController: context.read<MemoryController>(),
            navigationService: context.read<AiNavigationService>(),
            navigationController: context.read<AppNavigationController>(),
            agentToolController: context.read<AgentToolController>(),
            careAlertController: context.read<CareAlertController>(),
            careAlertNotificationService:
                context.read<CareAlertNotificationService>(),
          ),
          update: (context, profile, pet, petStats, conversation,
                  realtimeService, navigation, controller) =>
              controller ??
              VoiceAgentController(
                profileController: profile,
                petController: pet,
                petStatsController: petStats,
                conversationController: conversation,
                realtimeVoiceService: realtimeService,
                companionEngineService: context.read<CompanionEngineService>(),
                languageRoutingService: context.read<LanguageRoutingService>(),
                memoryController: context.read<MemoryController>(),
                navigationService: context.read<AiNavigationService>(),
                navigationController: navigation,
                agentToolController: context.read<AgentToolController>(),
                careAlertController: context.read<CareAlertController>(),
                careAlertNotificationService:
                    context.read<CareAlertNotificationService>(),
              ),
        ),
      ],
      child: Consumer<ProfileController>(
        builder: (context, profile, _) {
          final navigation = context.read<AppNavigationController>();
          return MaterialApp(
            title: '愛陪伴',
            navigatorKey: navigation.navigatorKey,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            builder: (context, child) {
              final mediaQuery = MediaQuery.of(context);
              return MediaQuery(
                data: mediaQuery.copyWith(
                  textScaler: TextScaler.linear(profile.fontScale),
                ),
                child: child ?? const SizedBox.shrink(),
              );
            },
            onGenerateRoute: _onGenerateRoute,
            // CR-0034：production 但 API base URL 仍指向本機 / 空時，不進入正式
            // 主流程（AppRoot 不掛載、不觸發載入），改顯示長者友善的暫不可用畫面，
            // 避免長者連到不存在的本機服務、看到一連串連線錯誤。
            home: AppConfig.isApiBaseUrlProductionSafe
                ? const AppRoot()
                : const _ServiceUnavailableView(),
          );
        },
      ),
    );
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) {
        return switch (settings.name) {
          AppRoute.album => const AlbumScreen(),
          AppRoute.marketplace => const MarketplaceScreen(),
          AppRoute.notification => const NotificationScreen(),
          AppRoute.careAlerts => const CareAlertScreen(),
          AppRoute.reminders => const ReminderScreen(),
          AppRoute.dailyCareTasks => const DailyCareTaskScreen(),
          AppRoute.memories => const MemoryManagementScreen(),
          AppRoute.puzzle => const PuzzleGameScreen(),
          AppRoute.conversationDetail => _conversationDetail(settings),
          _ => const MainShell(),
        };
      },
    );
  }

  Widget _conversationDetail(RouteSettings settings) {
    final args = settings.arguments;
    if (args is ConversationDetailArgs) {
      return ConversationDetailScreen(
        sessionId: args.sessionId,
        title: args.title,
      );
    }
    return const MainShell();
  }
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> with WidgetsBindingObserver {
  bool _initialized = false;
  String _lastDateKey = _dateKey();

  // CR-0006 Batch 3d：集中把登入後的 elderId 同步給記憶層。
  // 監聽 AuthController，登入 / 還原 / 登出時把 currentElderId 推進 MemoryController，
  // 不重建任何 controller、不動 conversation_controller、不動 Realtime。
  AuthController? _authControllerForSync;
  VoidCallback? _elderIdSyncListener;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    if (_authControllerForSync != null && _elderIdSyncListener != null) {
      _authControllerForSync!.removeListener(_elderIdSyncListener!);
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // 知情同意狀態與帳號無關，啟動時先載入，決定是否先擋同意流程。
      context.read<ConsentController>().load();
      final authController = context.read<AuthController>();
      final profileController = context.read<ProfileController>();
      final petStatsController = context.read<PetStatsController>();
      final checkInController = context.read<CheckInController>();
      final inventoryController = context.read<InventoryController>();
      final reminderController = context.read<ReminderController>();
      final dailyCareTaskController = context.read<DailyCareTaskController>();
      final careAlertController = context.read<CareAlertController>();
      final conversationController = context.read<ConversationController>();
      final notificationService = context.read<NotificationService>();
      final memoryController = context.read<MemoryController>();
      final petController = context.read<PetController>();
      final localStorageService = context.read<LocalStorageService>();
      final petStatsStorageService = context.read<PetStatsStorageService>();
      final checkInStorageService = context.read<CheckInStorageService>();
      final inventoryStorageService = context.read<InventoryStorageService>();
      final careAlertStorageService = context.read<CareAlertStorageService>();
      final reminderService = context.read<ReminderService>();

      // CR-0009：依「目前帳號的 elderId」切換本機資料命名空間 + 重載該帳號狀態。
      // 監聽 AuthController：登入 / 換帳號 / 登出 / 還原時，只要 currentElderId 變了，
      // 就重設各 storage 的命名空間（Demo/未登入=default_user 沿用既有資料），並重載
      // Profile（→ onboarding / 寵物名）、PetStats、對話。先掛 listener 再 restore，
      // 確保還原出的 session 也會套用。
      _authControllerForSync = authController;
      String? lastElderId;
      Future<void> applyAccount() async {
        final elderId = authController.currentElderId;
        if (elderId == lastElderId) return;
        lastElderId = elderId;
        localStorageService.setUserId(elderId);
        petStatsStorageService.setUserId(elderId);
        // CR-0012：簽到 / 背包 / 本地 Care Alert / 提醒的本機快取也依帳號隔離。
        checkInStorageService.setUserId(elderId);
        inventoryStorageService.setUserId(elderId);
        careAlertStorageService.setUserId(elderId);
        reminderService.setUserId(elderId);
        // CR-0025：日常照護任務也依帳號隔離；任務列表在進入「今日任務」頁時才向
        // 後端載入（避免每次啟動都打 API），這裡只切換命名空間。
        dailyCareTaskController.setElderId(elderId);
        memoryController.syncUserId(elderId);
        await profileController.load();
        // CR-0011：每個 elderId 各自記住寵物外觀，換帳號 / 登出 / 還原時一起重載。
        await petController.loadSkin();
        await petStatsController.load();
        await conversationController.loadHistory();
        // CR-0012：換帳號 / 登出 / 還原時，這四項也重載成「目前帳號自己的資料」，
        // 避免上一個正式帳號的簽到、背包、提醒、本地 alert 殘留到別的帳號（或 Demo）。
        await checkInController.load();
        await inventoryController.load();
        await careAlertController.loadAlerts();
        await reminderController.load();
        // CR-0031：每日簽到提醒一定排在 reminderController.load() 之後。
        // reminderController.load() 內部 rescheduleAll 會先 cancelAll（清掉所有
        // 已排程通知，含簽到提醒 10001），所以這裡最後再依「目前帳號今天是否已簽到」
        // 重新同步一則 10:00 簽到提醒，避免被清掉或重複排程。
        await notificationService.syncCheckInReminder(
          hasCheckedInToday: checkInController.hasCheckedInToday,
        );
      }

      // CR-0031：點簽到提醒通知時導回首頁（不另開新路由，沿用底部分頁）。
      notificationService.onCheckInReminderTapped = () {
        context.read<AppNavigationController>().selectShellIndex(0);
      };

      _elderIdSyncListener = () {
        applyAccount();
      };
      authController.addListener(_elderIdSyncListener!);
      await applyAccount(); // 初次（多為 default_user）；上面已含四項本機快取重載

      authController.restore();
      notificationService.initialize();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed) return;
    final currentDateKey = _dateKey();
    if (_lastDateKey == currentDateKey) return;
    _lastDateKey = currentDateKey;
    final checkInController = context.read<CheckInController>();
    final notificationService = context.read<NotificationService>();
    checkInController.refreshForDateChange();
    // CR-0031：跨日回到 App 時，重新同步今天的 10:00 簽到提醒。
    notificationService.syncCheckInReminder(
      hasCheckedInToday: checkInController.hasCheckedInToday,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 同意 gate 在最前面：未同意當前版本條款時，先擋住知情同意流程；
    // 同意後才落到既有登入 gate（authenticated → onboarding / MainShell）。
    return const ConsentGate();
  }
}

/// 知情同意 gate：依 [ConsentController.status] 分流。
///
/// - loading → 沿用溫暖等待畫面（不閃現同意流程）。
/// - needsConsent → ConsentScreen（同意後才能繼續）。
/// - granted → 落到既有 [AuthGate]，一字不動既有登入 / onboarding 流程。
class ConsentGate extends StatelessWidget {
  const ConsentGate({super.key});

  @override
  Widget build(BuildContext context) {
    final consent = context.watch<ConsentController>();
    switch (consent.status) {
      case ConsentStatus.loading:
        return const _AuthLoadingView();
      case ConsentStatus.needsConsent:
        return ConsentScreen(
          onAgreed: () => context.read<ConsentController>().grantConsent(),
        );
      case ConsentStatus.granted:
        return const AuthGate();
    }
  }
}

/// 登入 gate：依 [AuthController.status] 分流。
///
/// - loading → 溫暖等待畫面。
/// - unauthenticated / error → LoginScreen（error 不可死路，可重試 / 重新 demo 登入）。
/// - authenticated → 落回既有流程（profile loading → onboarding → MainShell），一字不改。
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    switch (auth.status) {
      case AuthStatus.loading:
        return const _AuthLoadingView();
      case AuthStatus.unauthenticated:
      case AuthStatus.error:
        // error 不可變成死路：一律回登入頁，長者可重試 / 重新 demo 登入。
        return LoginScreen(
          onRegister: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => RegisterScreen(
                onBackToLogin: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        );
      case AuthStatus.authenticated:
        // 落回既有流程，一字不改。
        final profile = context.watch<ProfileController>();
        if (profile.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!profile.hasCompletedOnboarding) {
          return const OnboardingScreen();
        }
        return const MainShell();
    }
  }
}

/// 啟動還原 / 登入呼叫中的溫暖等待畫面。
class _AuthLoadingView extends StatelessWidget {
  const _AuthLoadingView();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 24),
            Text(
              '正在準備你的陪伴空間…',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// CR-0034：正式環境設定尚未完成（API 位址未指向正式服務）時的長者友善畫面。
///
/// 不顯示任何工程字眼（URL / host / config 名稱），只告訴使用者暫時無法連線、
/// 請稍後再試或找服務人員協助，避免進入會一直連線失敗的正式主流程。
class _ServiceUnavailableView extends StatelessWidget {
  const _ServiceUnavailableView();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.favorite, size: 72, color: Color(0xFFFF8A80)),
              SizedBox(height: 24),
              Text(
                '服務正在準備中',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 16),
              Text(
                '現在還沒辦法連上，請稍後再打開看看。\n如果一直這樣，可以請家人或服務人員幫忙看看。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _dateKey() => DateTime.now().toIso8601String().split('T').first;

/// iOS 26 原生 Liquid Glass 底部列（UiKitView）容器高度（不含底部安全區）。
/// 原本 84 會讓浮動列顯得漂在畫面中間、離底部太遠；調小讓它更貼近螢幕底部，
/// 同時保留原生 Liquid Glass 材質（不動 Swift）。內容避讓的 padding 也沿用此值。
const double _kNativeHomeBarHeight = 56;

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final _pages = const [
    HomeScreen(),
    ShopScreen(),
    HistoryScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final navigation = context.watch<AppNavigationController>();
    final index =
        navigation.currentShellIndex < 0 ? 0 : navigation.currentShellIndex;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final bottomContentPadding = supportsLiquidGlassHomeBar && !keyboardOpen
        ? _kNativeHomeBarHeight + MediaQuery.paddingOf(context).bottom
        : 0.0;
    // CoachMarkHost 包住整個 shell：首次進首頁自動跑新手導覽，並把 spotlight
    // 疊在最上層（含底部導覽列）。導覽邏輯集中於 CoachMarkHost / CoachMarkController。
    return CoachMarkHost(
      homeVisible: index == 0,
      child: Scaffold(
        extendBody: supportsLiquidGlassHomeBar,
        resizeToAvoidBottomInset: index != 0,
        body: Padding(
          padding: EdgeInsets.only(bottom: bottomContentPadding),
          child: _pages[index],
        ),
        bottomNavigationBar: _HomeNavigationBar(
          selectedIndex: index,
          onDestinationSelected: navigation.selectShellIndex,
        ),
      ),
    );
  }
}

class _HomeNavigationBar extends StatefulWidget {
  const _HomeNavigationBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  State<_HomeNavigationBar> createState() => _HomeNavigationBarState();
}

class _HomeNavigationBarState extends State<_HomeNavigationBar> {
  static const _channel = MethodChannel('pet_companion/native_home_bar');

  static const _destinations = [
    NavigationDestination(icon: Icon(Icons.pets), label: '首頁'),
    NavigationDestination(icon: Icon(Icons.storefront), label: '商城'),
    NavigationDestination(icon: Icon(Icons.history), label: '紀錄'),
    NavigationDestination(icon: Icon(Icons.settings), label: '設定'),
  ];

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleNativeHomeBarCall);
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _handleNativeHomeBarCall(MethodCall call) async {
    if (call.method != 'tabSelected') return;
    final index = call.arguments as int?;
    if (index == null || index == widget.selectedIndex) return;
    widget.onDestinationSelected(index);
  }

  @override
  Widget build(BuildContext context) {
    // 把導覽用 key 掛在「整條底部列」的外層 KeyedSubtree 上（不論 Flutter
    // NavigationBar 或 iOS 原生 UiKitView），讓新手導覽都能取得這條列的螢幕框，
    // 再由 overlay 切出商城 / 紀錄 / 設定那一格高亮（CR-0016 v2：解決原生列
    // 拿不到框、底部 tab 不會亮的實機問題）。
    return KeyedSubtree(
      key: context.read<CoachMarkKeys>().navBarKey,
      child: _buildBar(context),
    );
  }

  Widget _buildBar(BuildContext context) {
    if (!supportsLiquidGlassHomeBar) {
      return NavigationBar(
        selectedIndex: widget.selectedIndex,
        onDestinationSelected: widget.onDestinationSelected,
        destinations: _destinations,
      );
    }

    return SizedBox(
      height: _kNativeHomeBarHeight + MediaQuery.paddingOf(context).bottom,
      child: UiKitView(
        key: ValueKey('native_home_bar_${widget.selectedIndex}'),
        viewType: 'native_home_bar',
        creationParams: {'selectedIndex': widget.selectedIndex},
        creationParamsCodec: const StandardMessageCodec(),
      ),
    );
  }
}
