import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pet_companion_app/config/app_config.dart';
import 'package:pet_companion_app/controllers/app_navigation_controller.dart';
import 'package:pet_companion_app/controllers/auth_controller.dart';
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
import 'package:pet_companion_app/onboarding/coach_mark_controller.dart';
import 'package:pet_companion_app/onboarding/coach_mark_keys.dart';
import 'package:pet_companion_app/screens/home_screen.dart';
import 'package:pet_companion_app/screens/settings_screen.dart';
import 'package:pet_companion_app/services/ai_navigation_service.dart';
import 'package:pet_companion_app/services/ai_tool_router.dart';
import 'package:pet_companion_app/services/asr_strategy_service.dart';
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

  testWidgets('HomeScreen idle state keeps conversation detail hidden',
      (tester) async {
    await binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => binding.setSurfaceSize(null));
    final harness = await _HomeHarness.create();
    addTearDown(harness.dispose);

    await tester.pumpWidget(_homeHost(harness));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('home-conversation-detail-scroll')),
      findsNothing,
    );

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    harness.dispose();
  });

  testWidgets('HomeScreen keeps pet stage simple and moves secondary actions',
      (tester) async {
    await binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => binding.setSurfaceSize(null));
    final harness = await _HomeHarness.create();
    addTearDown(harness.dispose);

    await tester.pumpWidget(_homeHost(harness));
    await tester.pump();

    expect(find.text('更換外觀'), findsNothing);
    expect(find.text('陪寵物玩'), findsNothing);
    expect(find.byTooltip('更多功能'), findsOneWidget);

    await tester.tap(find.byTooltip('更多功能'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('每日簽到'), findsOneWidget);
    expect(find.text('提醒'), findsOneWidget);
    expect(find.text('陪寵物玩'), findsOneWidget);
    expect(find.text('更換寵物外觀'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    harness.dispose();
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

  testWidgets('每日簽到彈窗在小螢幕（320 寬）不 overflow，且顯示標題與簽到按鈕', (tester) async {
    await binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => binding.setSurfaceSize(null));
    final harness = await _HomeHarness.create();
    addTearDown(harness.dispose);
    // 產生本月獎勵表，讓格子顯示金幣 / 禮物（更貼近實機畫面）。
    await harness.checkInController.load();

    await tester.pumpWidget(_homeHost(harness));
    await tester.pump();

    // 次要功能收在「更多功能」裡，首頁保持寵物與語音為主。
    await tester.tap(find.byTooltip('更多功能'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 點簽到入口開啟彈窗（有界 pump，不用 pumpAndSettle 以免卡在寵物動畫）。
    await tester.tap(
      find.ancestor(
        of: find.text('每日簽到'),
        matching: find.byType(ListTile),
      ),
    );
    await tester.pump();
    // pump 滿 1 秒：完成彈窗開啟動畫，並觸發首頁寵物的 1 秒 rest→listen 計時器，
    // 避免測試結束時殘留 pending timer（沿用 _pumpHomeScreen 慣例）。
    await tester.pump(const Duration(seconds: 1));

    // 開啟過程若 overflow，widget test 會拋例外導致失敗。
    expect(tester.takeException(), isNull);
    expect(find.textContaining('每日簽到'), findsOneWidget);
    expect(find.text('今天簽到'), findsOneWidget);
    expect(find.byType(GridView), findsOneWidget);

    // 乾淨版：格子裡不再放金幣（不出現 🪙），金幣只在下方獎勵摘要列。
    expect(find.textContaining('🪙'), findsNothing);
    // 預設選取今天，下方顯示「第 X 天獎勵：金幣 N」。
    expect(find.textContaining('天獎勵：金幣'), findsOneWidget);

    // 點第 4 天（禮物日）→ 下方獎勵摘要切換到第 4 天。
    await tester.tap(find.byKey(const ValueKey('calendar-day-4')));
    await tester.pump();
    expect(find.textContaining('第 4 天獎勵'), findsOneWidget);

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

  testWidgets('SettingsScreen「今日任務」入口依環境顯示（CR-0056 B2：production 隱藏 / dev 顯示）',
      (tester) async {
    final harness = await _HomeHarness.create();
    addTearDown(harness.dispose);

    await tester.pumpWidget(_settingsHost(harness));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    if (AppConfig.isProduction) {
      // 正式版完全隱藏入口（能力/路由保留，避免長者撞到死路頁）。
      expect(find.widgetWithText(FilledButton, '今日任務'), findsNothing);
    } else {
      // dev/test：入口照常可見（需捲動帶出）。
      await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, '今日任務'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.widgetWithText(FilledButton, '今日任務'), findsOneWidget);
    }
    // 同一區塊的「管理提醒」與環境無關，永遠存在。
    await tester.scrollUntilVisible(
      find.widgetWithText(OutlinedButton, '管理提醒'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.widgetWithText(OutlinedButton, '管理提醒'), findsOneWidget);
  });

  testWidgets('首頁「使用教學」入口存在且較淡，點擊會觸發重新觀看導覽（CR-0020）', (tester) async {
    await binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => binding.setSurfaceSize(null));
    final harness = await _HomeHarness.create();
    addTearDown(harness.dispose);
    final coach = CoachMarkController();
    addTearDown(coach.dispose);

    await tester.pumpWidget(_homeHost(harness, coach: coach));
    await tester.pump();

    // 教學入口收在更多功能裡，首頁不再塞一排小工具按鈕。
    expect(find.byTooltip('更多功能'), findsOneWidget);
    expect(coach.replayRequested, isFalse);

    // 點擊後仍觸發重新觀看新手導覽。
    await tester.tap(find.byTooltip('更多功能'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.scrollUntilVisible(
      find.text('使用教學'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(
      find.ancestor(
        of: find.text('使用教學'),
        matching: find.byType(ListTile),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(coach.replayRequested, isTrue);

    // 讓首頁寵物的 1 秒 rest→listen 計時器跑完，避免殘留 pending timer。
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    harness.dispose();
  });

  testWidgets('設定頁有「重新觀看新手導覽」按鈕，點擊觸發 replay 並切回首頁', (tester) async {
    final harness = await _HomeHarness.create();
    addTearDown(harness.dispose);
    final coachController = CoachMarkController();
    addTearDown(coachController.dispose);

    // 先切到非首頁分頁，確認點擊後會切回首頁（index 0）。
    harness.navigationController.selectShellIndex(3);

    await tester.pumpWidget(_settingsHostWithCoach(harness, coachController));
    await tester.pumpAndSettle();

    // 設定頁存在「重新觀看新手導覽」按鈕（在 ListView 下方，需捲動帶出）。
    await tester.scrollUntilVisible(
      find.text('重新觀看新手導覽'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('重新觀看新手導覽'), findsOneWidget);
    expect(coachController.replayRequested, isFalse);

    await tester.ensureVisible(find.text('重新觀看新手導覽'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '重新觀看新手導覽'));
    await tester.pump();

    // 點擊後請求 replay，並切回首頁分頁（CoachMarkHost 會在首頁就緒後開始導覽）。
    expect(coachController.replayRequested, isTrue);
    expect(harness.navigationController.currentShellIndex, 0);
  });

  testWidgets('設定頁「刪除帳號」需二次確認，第一關取消不會刪除', (tester) async {
    final harness = await _HomeHarness.create();
    addTearDown(harness.dispose);
    final auth = AuthController();
    addTearDown(auth.dispose);

    await tester.pumpWidget(_settingsHostWithAuth(harness, auth));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.widgetWithText(TextButton, '刪除帳號'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.widgetWithText(TextButton, '刪除帳號'));
    await tester.pumpAndSettle();

    // 第一次確認對話框出現。
    await tester.tap(find.widgetWithText(TextButton, '刪除帳號'));
    await tester.pumpAndSettle();
    expect(find.text('要刪除帳號嗎？'), findsOneWidget);
    expect(find.textContaining('伺服器上的帳號資料'), findsWidgets);
    expect(find.textContaining('這台手機裡的寵物、記憶、提醒與使用紀錄'), findsOneWidget);

    // 第一關按「取消」→ 不進入第二關、不刪除。
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('要刪除帳號嗎？'), findsNothing);
    expect(find.text('最後確認'), findsNothing);
  });

  testWidgets('設定頁「刪除帳號」兩次都確定 → 觸發刪除並登出', (tester) async {
    final harness = await _HomeHarness.create();
    addTearDown(harness.dispose);
    final auth = AuthController();
    addTearDown(auth.dispose);

    await tester.pumpWidget(_settingsHostWithAuth(harness, auth));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.widgetWithText(TextButton, '刪除帳號'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.widgetWithText(TextButton, '刪除帳號'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, '刪除帳號'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('繼續'));
    await tester.pumpAndSettle();

    // 第二關「最後確認」。
    expect(find.text('最後確認'), findsOneWidget);
    expect(find.textContaining('送出刪除要求並清除本機資料'), findsOneWidget);
    await tester.tap(find.text('確定刪除'));
    await tester.pumpAndSettle();

    // 測試環境 Firebase 不可用 → deleteCurrentUser no-op，仍會清本機 session 並登出。
    expect(auth.status, AuthStatus.unauthenticated);
  });

  testWidgets('設定頁提供支援說明，未設定 hosted URL 時不露 TODO', (tester) async {
    final harness = await _HomeHarness.create();
    addTearDown(harness.dispose);
    final auth = AuthController();
    addTearDown(auth.dispose);

    await tester.pumpWidget(_settingsHostWithAuth(harness, auth));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.textContaining('正式支援管道'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.textContaining('正式支援管道'), findsOneWidget);
    expect(find.textContaining('TODO'), findsNothing);
    expect(find.textContaining('placeholder'), findsNothing);
  });
}

Widget _settingsHostWithAuth(_HomeHarness harness, AuthController auth) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthController>.value(value: auth),
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
      Provider<CoachMarkKeys>(create: (_) => CoachMarkKeys()),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: SettingsScreen(),
      ),
    ),
  );
}

Widget _settingsHostWithCoach(
  _HomeHarness harness,
  CoachMarkController coachController,
) {
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
      ChangeNotifierProvider<AppNavigationController>.value(
        value: harness.navigationController,
      ),
      ChangeNotifierProvider<CoachMarkController>.value(value: coachController),
      Provider<CoachMarkKeys>(create: (_) => CoachMarkKeys()),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: SettingsScreen(),
      ),
    ),
  );
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

Widget _homeHost(
  _HomeHarness harness, {
  double textScale = 1.0,
  CoachMarkController? coach,
}) {
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
      if (coach == null)
        ChangeNotifierProvider<CoachMarkController>(
          create: (_) => CoachMarkController(),
        )
      else
        ChangeNotifierProvider<CoachMarkController>.value(value: coach),
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
      Provider<CoachMarkKeys>(create: (_) => CoachMarkKeys()),
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
      companionChatService: CompanionChatService(),
      reminderController: ReminderController(
        reminderService: ReminderService(),
        notificationService: NotificationService(),
      ),
      useMockChat: true,
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
      sttService: MockSpeechToTextService(),
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
