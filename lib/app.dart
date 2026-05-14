import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'controllers/app_navigation_controller.dart';
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
import 'screens/conversation_detail_screen.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/memory_management_screen.dart';
import 'screens/notification_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/puzzle_game_screen.dart';
import 'screens/reminder_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/shop_screen.dart';
import 'services/ai_tool_router.dart';
import 'services/ai_navigation_service.dart';
import 'services/check_in_storage_service.dart';
import 'services/companion_content_service.dart';
import 'services/emotion_services.dart';
import 'services/inventory_storage_service.dart';
import 'services/local_storage_service.dart';
import 'services/memory_service.dart';
import 'services/mock_ai_service.dart';
import 'services/mock_shop_service.dart';
import 'services/mock_speech_to_text_service.dart';
import 'services/notification_service.dart';
import 'services/pet_stats_storage_service.dart';
import 'services/realtime_voice_service.dart';
import 'services/reminder_service.dart';
import 'services/search_service.dart';
import 'services/shop_service.dart';
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
        Provider(create: (_) => const ShopService()),
        Provider(create: (_) => MemoryService()),
        Provider(create: (_) => const AiNavigationService()),
        Provider(create: (_) => ReminderService()),
        Provider(create: (_) => NotificationService()),
        Provider(create: (_) => const EmotionFusionService()),
        Provider(create: (_) => const PetEmotionMapper()),
        ChangeNotifierProvider(create: (_) => AppNavigationController()),
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
        Provider(create: (_) => RealtimeVoiceService()),
        ProxyProvider6<ProfileController, TaskController, WalletController,
            MockShopService, WebSearchService, MockAiService, AiToolRouter>(
          update: (context, profile, task, wallet, shop, web, ai, __) =>
              AiToolRouter(
            profileController: profile,
            taskController: task,
            walletController: wallet,
            shopService: shop,
            webSearchService: web,
            mockAiService: ai,
            companionContentService: context.read<CompanionContentService>(),
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
            memoryController: context.read<MemoryController>(),
            navigationService: context.read<AiNavigationService>(),
            navigationController: context.read<AppNavigationController>(),
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
                memoryController: context.read<MemoryController>(),
                navigationService: context.read<AiNavigationService>(),
                navigationController: navigation,
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
            home: const _AppRoot(),
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

class _AppRoot extends StatefulWidget {
  const _AppRoot();

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> with WidgetsBindingObserver {
  bool _initialized = false;
  String _lastDateKey = _dateKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
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
      final profileController = context.read<ProfileController>();
      final petStatsController = context.read<PetStatsController>();
      final checkInController = context.read<CheckInController>();
      final inventoryController = context.read<InventoryController>();
      final reminderController = context.read<ReminderController>();
      final conversationController = context.read<ConversationController>();
      final notificationService = context.read<NotificationService>();

      profileController.load();
      petStatsController.load();
      checkInController.load();
      inventoryController.load();
      reminderController.load();
      await conversationController.loadHistory();
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
    final profile = context.watch<ProfileController>();
    if (profile.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!profile.hasCompletedOnboarding) {
      return const OnboardingScreen();
    }
    return const MainShell();
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
    final bottomContentPadding = supportsLiquidGlassHomeBar
        ? 84 + MediaQuery.paddingOf(context).bottom
        : 0.0;
    return Scaffold(
      extendBody: supportsLiquidGlassHomeBar,
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
