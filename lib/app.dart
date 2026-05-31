import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'controllers/app_navigation_controller.dart';
import 'controllers/agent_tool_controller.dart';
import 'controllers/auth_controller.dart';
import 'controllers/care_alert_controller.dart';
import 'controllers/conversation_controller.dart';
import 'controllers/check_in_controller.dart';
import 'controllers/inventory_controller.dart';
import 'controllers/memory_controller.dart';
import 'controllers/pet_controller.dart';
import 'controllers/pet_stats_controller.dart';
import 'controllers/profile_controller.dart';
import 'controllers/reminder_controller.dart';
import 'controllers/task_controller.dart';
import 'controllers/voice_agent_controller.dart';
import 'controllers/wallet_controller.dart';
import 'routes/app_routes.dart';
import 'screens/album_screen.dart';
import 'screens/care_alert_screen.dart';
import 'screens/conversation_detail_screen.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/memory_management_screen.dart';
import 'screens/notification_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/puzzle_game_screen.dart';
import 'screens/register_screen.dart';
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
import 'services/companion_content_service.dart';
import 'services/companion_engine_service.dart';
import 'services/contact_lookup_service.dart';
import 'services/companion_reply_strategy_service.dart';
import 'services/emotion_services.dart';
import 'services/inventory_storage_service.dart';
import 'services/local_storage_service.dart';
import 'services/language_routing_service.dart';
import 'services/memory_service.dart';
import 'services/mock_ai_service.dart';
import 'services/mock_shop_service.dart';
import 'services/mock_speech_to_text_service.dart';
import 'services/native_tool_executor_service.dart';
import 'services/notification_service.dart';
import 'services/pet_stats_storage_service.dart';
import 'services/realtime_voice_service.dart';
import 'services/reminder_service.dart';
import 'services/search_service.dart';
import 'services/shop_service.dart';
import 'services/taigi_asr_strategy.dart';
import 'services/taigi_asr_service.dart';
import 'services/text_to_speech_service.dart';
import 'services/web_search_service.dart';
import 'utils/platform_liquid_glass.dart';

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
        Provider(create: (_) => MemoryService()),
        Provider(create: (_) => const CompanionEngineService()),
        Provider(create: (_) => const CompanionReplyStrategyService()),
        Provider(create: (_) => const AiNavigationService()),
        Provider(create: (_) => ReminderService()),
        Provider(create: (_) => NotificationService()),
        Provider(create: (_) => const EmotionFusionService()),
        Provider(create: (_) => const PetEmotionMapper()),
        Provider(create: (_) => AgentRouterService()),
        Provider(create: (_) => CareAlertNotificationService()),
        ChangeNotifierProvider(create: (_) => AppNavigationController()),
        ChangeNotifierProvider(
          create: (_) => AuthController(authService: AuthService()),
        ),
        ChangeNotifierProvider(
          create: (context) =>
              ProfileController(context.read<LocalStorageService>()),
        ),
        ProxyProvider<ProfileController, NativeToolExecutorService>(
          update: (_, profile, previous) =>
              previous ??
              NativeToolExecutorService(
                contactLookup: ContactLookupService(profile),
              ),
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
        ChangeNotifierProvider(create: (_) => PetController()),
        Provider(create: (_) => MockShopService()),
        Provider(create: (_) => WebSearchService()),
        ProxyProvider<WebSearchService, CompanionContentService>(
          update: (_, webSearch, __) => CompanionContentService(webSearch),
        ),
        Provider(create: (_) => MockAiService()),
        Provider(create: (_) => MockSpeechToTextService()),
        Provider(create: (_) => SearchService()),
        Provider(create: (_) => TextToSpeechService()),
        Provider(create: (_) => TaigiAsrService()),
        Provider(create: (_) => RealtimeVoiceService()),
        Provider(
          create: (_) => AsrStrategyService(
            strategies: const [
              OpenAiRealtimeAsrStrategy(),
              MockTaigiAsrStrategy(),
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
            mockSttService: context.read<MockSpeechToTextService>(),
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
                mockSttService: mockStt,
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
            theme: ThemeData(
              colorSchemeSeed: Colors.indigo,
              useMaterial3: true,
              scaffoldBackgroundColor: const Color(0xFFF7F8FC),
            ),
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
            home: const AppRoot(),
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
          AppRoute.notification => const NotificationScreen(),
          AppRoute.careAlerts => const CareAlertScreen(),
          AppRoute.reminders => const ReminderScreen(),
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
      final authController = context.read<AuthController>();
      final profileController = context.read<ProfileController>();
      final petStatsController = context.read<PetStatsController>();
      final checkInController = context.read<CheckInController>();
      final inventoryController = context.read<InventoryController>();
      final reminderController = context.read<ReminderController>();
      final careAlertController = context.read<CareAlertController>();
      final conversationController = context.read<ConversationController>();
      final notificationService = context.read<NotificationService>();
      final memoryController = context.read<MemoryController>();
      final localStorageService = context.read<LocalStorageService>();
      final petStatsStorageService = context.read<PetStatsStorageService>();

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
        memoryController.syncUserId(elderId);
        await profileController.load();
        await petStatsController.load();
        await conversationController.loadHistory();
      }

      _elderIdSyncListener = () {
        applyAccount();
      };
      authController.addListener(_elderIdSyncListener!);
      await applyAccount(); // 初次（多為 default_user）

      authController.restore();
      checkInController.load();
      inventoryController.load();
      reminderController.load();
      careAlertController.loadAlerts();
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
    context.read<CheckInController>().refreshForDateChange();
  }

  @override
  Widget build(BuildContext context) {
    // 登入 gate 只在最前面加一層；authenticated 後落回既有 onboarding/MainShell 分流。
    return const AuthGate();
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

String _dateKey() => DateTime.now().toIso8601String().split('T').first;

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
        ? 84 + MediaQuery.paddingOf(context).bottom
        : 0.0;
    return Scaffold(
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
    if (!supportsLiquidGlassHomeBar) {
      return NavigationBar(
        selectedIndex: widget.selectedIndex,
        onDestinationSelected: widget.onDestinationSelected,
        destinations: _destinations,
      );
    }

    return SizedBox(
      height: 84 + MediaQuery.paddingOf(context).bottom,
      child: UiKitView(
        key: ValueKey('native_home_bar_${widget.selectedIndex}'),
        viewType: 'native_home_bar',
        creationParams: {'selectedIndex': widget.selectedIndex},
        creationParamsCodec: const StandardMessageCodec(),
      ),
    );
  }
}
