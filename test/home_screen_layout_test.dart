import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pet_companion_app/config/app_config.dart';
import 'package:pet_companion_app/utils/preference_text_scaler.dart';
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
import 'package:pet_companion_app/widgets/pet_avatar.dart';
import 'package:pet_companion_app/widgets/inventory_item_card.dart';
import 'package:pet_companion_app/models/pet_status.dart';
import 'package:pet_companion_app/widgets/source_reference_list.dart';
import 'package:pet_companion_app/widgets/ui/primary_action_button.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('daily invitation uses the existing silent pet response without care-task rewards', (tester) async {
    await binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => binding.setSurfaceSize(null));
    final harness = await _HomeHarness.create();
    addTearDown(harness.dispose);
    final coins = harness.walletController.coins;
    final tasks = Map<String, bool>.from(harness.profileController.taskState);
    await tester.pumpWidget(_homeHost(harness));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('daily-moment-pat')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('daily-moment-pat')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(harness.petController.message, '謝謝你摸摸我，我就在這裡陪你。');
    expect(find.byKey(const ValueKey('daily-moment-resolved')), findsOneWidget);
    expect(harness.walletController.coins, coins);
    expect(harness.profileController.taskState, tasks);
    expect(harness.petController.mode, PetMode.happy);
    expect(harness.petController.state.isSpeaking, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpWidget(const SizedBox.shrink());
    harness.dispose();
  });

  testWidgets(
      '4x combined system and preference size keeps main operations reachable',
      (tester) async {
    await binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => binding.setSurfaceSize(null));
    final harness = await _HomeHarness.create();
    addTearDown(harness.dispose);
    await harness.profileController.setFontScale(2);
    await tester
        .pumpWidget(_homeHost(harness, textScale: 2, applyPreference: true));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.byType(PrimaryActionButton)).bottom,
        lessThanOrEqualTo(568));
    expect(
        MediaQuery.textScalerOf(
                tester.element(find.byType(PrimaryActionButton)))
            .scale(21),
        84);
    await tester.tap(find.text('打字'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('跟寵物說一句話'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'a delayed tap response does not overwrite a newer typing interaction',
      (tester) async {
    final tts = _DelayedStopTts();
    final harness = await _HomeHarness.create(ttsService: tts);
    addTearDown(harness.dispose);
    await tester.pumpWidget(_homeHost(harness));
    await tester.pump();
    harness.petController.setMode(PetMode.talking, isSpeaking: true);
    await tester.pump();
    final intimacy = harness.petStatsController.intimacy;
    await tester.tap(find.byType(PetAvatar));
    await tester.tap(find.text('打字'));
    await tester.pump();
    tts.stopped.complete();
    await tester.pump();
    expect(find.text('跟寵物說一句話'), findsOneWidget);
    expect(find.text('謝謝你摸摸我，我就在這裡陪你。'), findsNothing);
    expect(harness.petStatsController.intimacy, intimacy);
    expect(harness.voiceAgentController.hasOpenRealtimeSession, isFalse);
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'tap feeding stops greeting first and repeated taps consume only once',
      (tester) async {
    await binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => binding.setSurfaceSize(null));
    final tts = _DelayedStopTts();
    final harness = await _HomeHarness.create(ttsService: tts);
    addTearDown(harness.dispose);
    final food = const ShopService().allItems().first;
    await harness.inventoryController.addFromShop(food);
    await harness.inventoryController.addFromShop(food);
    await tester.pumpWidget(_homeHost(harness));
    await tester.pump();
    await tester.tap(find.byTooltip('更多功能'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.text('背包'));
    await tester.tap(find.text('背包'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    harness.petController.setMode(PetMode.talking, isSpeaking: true);
    await tester.pump();
    await tester.tap(find.byType(InventoryItemCard));
    await tester.tap(find.byType(InventoryItemCard));
    await tester.pump();
    expect(tts.stops, 1);
    expect(harness.inventoryController.totalQuantity, 2);
    tts.stopped.complete();
    await tester.pump();
    expect(harness.inventoryController.totalQuantity, 1);
    expect(harness.voiceAgentController.hasOpenRealtimeSession, isFalse);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('收起背包'));
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      '2x small screen keeps voice, typing, full reply and sheet return reachable',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => binding.setSurfaceSize(null));
    final harness = await _HomeHarness.create();
    addTearDown(harness.dispose);
    final reply = List.filled(12, '今天買的番茄很漂亮，我陪你慢慢聊。').join();
    harness.conversationController.showPetBubbleMessage(reply);
    await tester.pumpWidget(_homeHost(harness, textScale: 2));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.byType(PrimaryActionButton)).bottom,
        lessThanOrEqualTo(568));
    await tester.tap(find.text('打字'));
    await tester.pump();
    expect(find.text('跟寵物說一句話'), findsOneWidget);
    await tester.tap(find.text('收起'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('home-full-reply')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SelectableText), findsOneWidget);
    expect(tester.widget<SelectableText>(find.byType(SelectableText)).data,
        contains(reply));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('返回首頁'));
    await tester.tap(find.text('返回首頁'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await _openTogether(tester);
    expect(find.bySemanticsLabel(RegExp('小伴邀請你互動')), findsOneWidget);
    await tester.tap(find.text('返回首頁'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(PrimaryActionButton), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 9));
    semantics.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('pet numbers appear only in scrollable details at 2x',
      (tester) async {
    await binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => binding.setSurfaceSize(null));
    final harness = await _HomeHarness.create();
    addTearDown(harness.dispose);
    await tester.pumpWidget(_homeHost(harness, textScale: 2));
    await tester.pump();
    expect(find.text('親密'), findsNothing);
    await tester
        .ensureVisible(find.byKey(const ValueKey('home-status-details')));
    await tester.tap(find.byKey(const ValueKey('home-status-details')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('親密'), findsOneWidget);
    expect(find.text('飽足'), findsOneWidget);
    expect(find.text('心情'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('返回首頁'));
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'font preference accepts 2x and normalizes stored out of range values',
      (tester) async {
    final harness = await _HomeHarness.create();
    addTearDown(harness.dispose);
    await harness.profileController.setFontScale(2);
    expect(harness.profileController.fontScale, 2);
    await harness.profileController.load();
    expect(harness.profileController.fontScale, 2);
    await harness.profileController.setFontScale(double.nan);
    expect(harness.profileController.fontScale, 1);
    await harness.profileController.setFontScale(.9);
    expect(harness.profileController.fontScale, .9);
    await LocalStorageService().saveProfile(
      harness.profileController.profile.copyWith(fontScale: 9),
    );
    await harness.profileController.load();
    expect(harness.profileController.fontScale, 2);
  });

  testWidgets('HomeScreen does not overflow at small height', (tester) async {
    await binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => binding.setSurfaceSize(null));
    final harness = await _HomeHarness.create();
    addTearDown(harness.dispose);

    await _pumpHomeScreen(tester, harness);
  });

  testWidgets('HomeScreen idle state gives a clear no-microphone invitation', (
    tester,
  ) async {
    await binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => binding.setSurfaceSize(null));
    final harness = await _HomeHarness.create();
    addTearDown(harness.dispose);

    await tester.pumpWidget(_homeHost(harness));
    await tester.pump();

    expect(find.textContaining('不用開麥克風'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-invitation-pat')), findsNothing);
    await _openTogether(tester);
    expect(find.byKey(const ValueKey('home-invitation-pat')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-invitation-sit')), findsOneWidget);

    await tester.pump(const Duration(seconds: 9));
    await tester.pumpWidget(const SizedBox.shrink());
    harness.dispose();
  });

  testWidgets('HomeScreen text fallback is discoverable and opens input', (
    tester,
  ) async {
    await binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => binding.setSurfaceSize(null));
    final harness = await _HomeHarness.create();
    addTearDown(harness.dispose);

    await tester.pumpWidget(_homeHost(harness));
    await tester.pump();

    expect(find.text('打字'), findsOneWidget);
    expect(find.text('跟寵物說一句話'), findsNothing);

    await tester.tap(find.text('打字'));
    await tester.pump();

    expect(find.text('收起'), findsOneWidget);
    expect(find.text('跟寵物說一句話'), findsOneWidget);

    await tester.pump(const Duration(seconds: 9));
    await tester.pumpWidget(const SizedBox.shrink());
    harness.dispose();
  });

  testWidgets('HomeScreen keeps pet stage simple and moves secondary actions', (
    tester,
  ) async {
    await binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => binding.setSurfaceSize(null));
    final harness = await _HomeHarness.create();
    addTearDown(harness.dispose);

    await tester.pumpWidget(_homeHost(harness));
    await tester.pump();

    expect(find.text('更換外觀'), findsNothing);
    expect(find.text('陪寵物玩'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '一起陪伴'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '更多'), findsOneWidget);
    expect(find.byTooltip('更多功能'), findsOneWidget);

    await tester.tap(find.byTooltip('更多功能'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('還想幫小伴做什麼？'), findsOneWidget);
    expect(find.text('平常只要按麥克風跟寵物說話，其他功能都先放在這裡。'), findsOneWidget);
    expect(find.text('常用功能'), findsOneWidget);
    expect(find.text('照顧寵物'), findsOneWidget);
    expect(find.text('其他'), findsOneWidget);
    expect(find.text('每日簽到'), findsOneWidget);
    expect(find.text('提醒'), findsOneWidget);
    expect(find.text('陪寵物玩'), findsOneWidget);
    expect(find.text('更換外觀'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    harness.dispose();
  });

  testWidgets('HomeScreen pet tap gives feedback without leaving home', (
    tester,
  ) async {
    await binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => binding.setSurfaceSize(null));
    final harness = await _HomeHarness.create();
    addTearDown(harness.dispose);

    await tester.pumpWidget(_homeHost(harness));
    await tester.pump();

    await tester.tap(find.byType(PetAvatar));
    await tester.pump();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(
      find.byKey(const ValueKey('pet-interaction-effect-pat')),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    harness.dispose();
  });

  testWidgets(
    'HomeScreen local invitation responds offline and debounces taps',
    (tester) async {
      await binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => binding.setSurfaceSize(null));
      final harness = await _HomeHarness.create();
      addTearDown(harness.dispose);

      await tester.pumpWidget(_homeHost(harness));
      await tester.pump();
      final initialIntimacy = harness.petStatsController.intimacy;

      final pat = find.byType(PetAvatar);
      await tester.tap(pat);
      await tester.tap(pat);
      await tester.pump();

      expect(find.text('謝謝你摸摸我，我就在這裡陪你。'), findsOneWidget);
      expect(harness.voiceAgentController.hasOpenRealtimeSession, isFalse);
      expect(harness.petStatsController.intimacy, initialIntimacy + 1);
      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(seconds: 9));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'HomeScreen keeps chat and touch available for legacy zero stats',
    (tester) async {
      await binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => binding.setSurfaceSize(null));
      final harness = await _HomeHarness.create(
        initialPreferences: const {
          'petStats.intimacy': 0,
          'petStats.fullness': 0,
          'petStats.moodValue': 0,
        },
      );
      addTearDown(harness.dispose);

      await tester.pumpWidget(_homeHost(harness));
      await tester.pump();

      expect(harness.petStatsController.lifeState.name, 'alive');
      expect(find.byType(PetAvatar), findsOneWidget);
      expect(find.text('打字'), findsOneWidget);
      final micButton = tester.widget<PrimaryActionButton>(
        find.byType(PrimaryActionButton),
      );
      expect(micButton.onPressed, isNotNull);

      await _openTogether(tester);
      await tester.tap(find.byKey(const ValueKey('home-invitation-sit')));
      await tester.tap(find.byKey(const ValueKey('home-invitation-sit')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(HomeScreen), findsOneWidget);
      await tester.pump();
      expect(find.textContaining('不說話也沒關係'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(seconds: 9));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'HomeScreen ignores a late first greeting after interaction starts',
    (tester) async {
      await binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => binding.setSurfaceSize(null));
      final greetingService = _DeferredGreetingMemoryService();
      final harness = await _HomeHarness.create(memoryService: greetingService);
      addTearDown(harness.dispose);

      await tester.pumpWidget(_homeHost(harness));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(greetingService.requested, isTrue);

      await tester.tap(find.byType(PetAvatar));
      await tester.pump();
      greetingService.complete('這是一則太晚回來的問候');
      await tester.pump();

      expect(find.text('謝謝你摸摸我，我就在這裡陪你。'), findsOneWidget);
      expect(find.text('這是一則太晚回來的問候'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(seconds: 9));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('HomeScreen celebrates when a care task is completed', (
    tester,
  ) async {
    await binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => binding.setSurfaceSize(null));
    final harness = await _HomeHarness.create();
    addTearDown(harness.dispose);

    await tester.pumpWidget(_homeHost(harness));
    await tester.pump();

    await harness.taskController.completeTaskById('drinkWater');
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('pet-interaction-effect-celebrate')),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    harness.dispose();
  });

  testWidgets('HomeScreen handles long AI reply and sources without overflow', (
    tester,
  ) async {
    await binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => binding.setSurfaceSize(null));
    final harness = await _HomeHarness.create();
    addTearDown(harness.dispose);
    harness.conversationController.appendExternalTurn(
      ConversationTurn(
        timestamp: DateTime.now(),
        userText: '幫我查一下睡不好可以怎麼辦',
        petReply: List.filled(10, '我聽得出來你昨晚很辛苦，我先陪你慢慢把身體放鬆下來。').join(),
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

  testWidgets('HomeScreen 對話資訊出現前後維持相同寵物尺寸', (tester) async {
    await binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => binding.setSurfaceSize(null));
    final harness = await _HomeHarness.create();
    addTearDown(harness.dispose);

    await tester.pumpWidget(_homeHost(harness));
    await tester.pump();
    final idleSize = tester.getSize(
      find.byKey(const ValueKey('home-pet-avatar')),
    );

    harness.conversationController.appendExternalTurn(
      ConversationTurn(
        timestamp: DateTime.now(),
        userText: '今天想跟你說說話',
        petReply: '我在這裡陪你，我們慢慢聊。',
        toolName: '',
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('home-full-reply')),
      findsOneWidget,
    );
    final conversationSize = tester.getSize(
      find.byKey(const ValueKey('home-pet-avatar')),
    );
    expect(conversationSize, idleSize);
    expect(conversationSize.height, greaterThanOrEqualTo(180));
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    harness.dispose();
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
    await tester.tap(find.text('每日簽到'));
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

  testWidgets('HomeScreen hides ASR route and emotion fusion debug text', (
    tester,
  ) async {
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

  testWidgets('SourceReferenceList shows at most two product sources', (
    tester,
  ) async {
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

  testWidgets('HomeScreen does not overflow with 1.3 text scale', (
    tester,
  ) async {
    await binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => binding.setSurfaceSize(null));
    final harness = await _HomeHarness.create();
    addTearDown(harness.dispose);
    harness.conversationController.showPetBubbleMessage(
      '我在這裡陪你，慢慢說就好。今天如果覺得心裡悶，我們可以先不用急著解決。',
    );

    await tester.pumpWidget(_homeHost(harness, textScale: 1.3));
    await tester.pump();
    expect(tester.takeException(), isNull);

    final playContext = tester.element(find.text('一起陪伴'));
    final effectiveFontSize = MediaQuery.textScalerOf(playContext).scale(17);
    expect(effectiveFontSize, closeTo(22.1, 0.01));

    await tester.pump(const Duration(seconds: 9));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('HomeScreen invitation stays accessible at 1.3 text scale', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => binding.setSurfaceSize(null));
    final harness = await _HomeHarness.create();
    addTearDown(harness.dispose);

    await tester.pumpWidget(_homeHost(harness, textScale: 1.3));
    await tester.pump();

    await _openTogether(tester);
    expect(
      find.bySemanticsLabel(RegExp('小伴邀請你互動，不需要開啟麥克風')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('home-invitation-pat')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-invitation-sit')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(seconds: 9));
    expect(tester.takeException(), isNull);
    semantics.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('設定語言顯示待連線狀態而非提前宣稱已套用', (tester) async {
    final harness = await _HomeHarness.create();
    addTearDown(harness.dispose);
    await tester.pumpWidget(_settingsHost(harness));
    await tester.pumpAndSettle();
    await tester.tap(find.text('看與聽'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('台語即時語音'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('台語即時語音'));
    await tester.pumpAndSettle();

    expect(harness.profileController.voiceLanguageMode.name, 'taigiRealtime');
    expect(find.text('聊天語言'), findsOneWidget);
    expect(find.text('已記住語言偏好，下次連線時套用。'), findsOneWidget);
    expect(find.text('聊天語言已更新。'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SettingsScreen hides dev panels when SHOW_DEV_PANELS is off', (
    tester,
  ) async {
    final harness = await _HomeHarness.create();
    addTearDown(harness.dispose);

    await tester.pumpWidget(_settingsHost(harness));
    await tester.pumpAndSettle();

    await tester.tap(find.text('帳號'));
    await tester.pumpAndSettle();

    // SHOW_DEV_PANELS 預設為 false：開發用面板不應出現在使用者設定頁。
    expect(tester.takeException(), isNull);
    expect(find.text('進階診斷（開發人員）'), findsNothing);
    expect(find.text('Realtime Diagnostics'), findsNothing);
    expect(find.text('Companion Debug Panel'), findsNothing);
    expect(find.text('AI Agent 工具測試'), findsNothing);
  });

  testWidgets('設定頁在小螢幕與 1.3 倍字級維持四個清楚分類', (tester) async {
    await binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => binding.setSurfaceSize(null));
    final harness = await _HomeHarness.create();
    addTearDown(harness.dispose);

    await tester.pumpWidget(_settingsHost(harness, textScale: 1.3));
    await tester.pumpAndSettle();

    expect(find.text('寵物'), findsOneWidget);
    expect(find.text('看與聽'), findsOneWidget);
    expect(find.text('陪伴'), findsOneWidget);
    expect(find.text('帳號'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SettingsScreen「今日任務」入口依正式功能旗標顯示', (tester) async {
    final harness = await _HomeHarness.create();
    addTearDown(harness.dispose);

    await tester.pumpWidget(_settingsHost(harness));
    await tester.pumpAndSettle();

    await tester.tap(find.text('陪伴'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    if (AppConfig.dailyCareTasksVisible) {
      await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, '今日任務'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.widgetWithText(FilledButton, '今日任務'), findsOneWidget);
    } else {
      expect(find.widgetWithText(FilledButton, '今日任務'), findsNothing);
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
    await tester.tap(find.text('使用教學'));
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

    await tester.tap(find.text('帳號'));
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

    await tester.tap(find.text('帳號'));
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

    await tester.tap(find.text('帳號'));
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

    await tester.tap(find.text('帳號'));
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
      Provider<LocalStorageService>.value(value: harness.localStorage),
      ChangeNotifierProvider<AuthController>.value(value: auth),
      ChangeNotifierProvider<ProfileController>.value(
        value: harness.profileController,
      ),
      ChangeNotifierProvider<PetController>.value(value: harness.petController),
      ChangeNotifierProvider<ConversationController>.value(
        value: harness.conversationController,
      ),
      ChangeNotifierProvider<VoiceAgentController>.value(
        value: harness.voiceAgentController,
      ),
      Provider<RealtimeVoiceService>.value(value: harness.realtimeVoiceService),
      Provider<CoachMarkKeys>(create: (_) => CoachMarkKeys()),
    ],
    child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
  );
}

Widget _settingsHostWithCoach(
  _HomeHarness harness,
  CoachMarkController coachController,
) {
  return MultiProvider(
    providers: [
      Provider<LocalStorageService>.value(value: harness.localStorage),
      ChangeNotifierProvider<ProfileController>.value(
        value: harness.profileController,
      ),
      ChangeNotifierProvider<PetController>.value(value: harness.petController),
      ChangeNotifierProvider<ConversationController>.value(
        value: harness.conversationController,
      ),
      ChangeNotifierProvider<VoiceAgentController>.value(
        value: harness.voiceAgentController,
      ),
      Provider<RealtimeVoiceService>.value(value: harness.realtimeVoiceService),
      ChangeNotifierProvider<AppNavigationController>.value(
        value: harness.navigationController,
      ),
      ChangeNotifierProvider<CoachMarkController>.value(value: coachController),
      Provider<CoachMarkKeys>(create: (_) => CoachMarkKeys()),
    ],
    child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
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

Future<void> _openTogether(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(OutlinedButton, '一起陪伴'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Widget _homeHost(
  _HomeHarness harness, {
  double textScale = 1.0,
  bool applyPreference = false,
  CoachMarkController? coach,
}) {
  return MultiProvider(
    providers: [
      Provider<LocalStorageService>.value(value: harness.localStorage),
      ChangeNotifierProvider<ProfileController>.value(
        value: harness.profileController,
      ),
      ChangeNotifierProvider<PetController>.value(value: harness.petController),
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
      ChangeNotifierProvider<TaskController>.value(
        value: harness.taskController,
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
              textScaler: PreferenceTextScaler(TextScaler.linear(textScale),
                  applyPreference ? harness.profileController.fontScale : 1)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const Scaffold(body: HomeScreen()),
    ),
  );
}

Widget _settingsHost(_HomeHarness harness, {double textScale = 1.0}) {
  return MultiProvider(
    providers: [
      Provider<LocalStorageService>.value(value: harness.localStorage),
      ChangeNotifierProvider<ProfileController>.value(
        value: harness.profileController,
      ),
      ChangeNotifierProvider<PetController>.value(value: harness.petController),
      ChangeNotifierProvider<ConversationController>.value(
        value: harness.conversationController,
      ),
      ChangeNotifierProvider<VoiceAgentController>.value(
        value: harness.voiceAgentController,
      ),
      Provider<RealtimeVoiceService>.value(value: harness.realtimeVoiceService),
      Provider<CoachMarkKeys>(create: (_) => CoachMarkKeys()),
    ],
    child: MaterialApp(
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(textScaler: TextScaler.linear(textScale)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const Scaffold(body: SettingsScreen()),
    ),
  );
}

class _DelayedStopTts extends TextToSpeechService {
  final stopped = Completer<void>();
  int stops = 0;
  @override
  Future<void> stop() {
    stops += 1;
    return stopped.future;
  }
}

class _HomeHarness {
  _HomeHarness({
    required this.localStorage,
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

  final LocalStorageService localStorage;
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

  static Future<_HomeHarness> create({
    Map<String, Object> initialPreferences = const {},
    MemoryService? memoryService,
    TextToSpeechService? ttsService,
  }) async {
    SharedPreferences.setMockInitialValues(initialPreferences);
    final localStorage = LocalStorageService();
    final profileController = ProfileController(localStorage);
    await profileController.completeOnboarding('小伴');
    await profileController.setTtsEnabled(false);

    final petController = PetController();
    final petStatsController = PetStatsController(PetStatsStorageService());
    await petStatsController.load();
    final checkInController = CheckInController(CheckInStorageService());
    final inventoryController = InventoryController(InventoryStorageService());
    final memoryController = MemoryController(memoryService ?? MemoryService());
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
        strategies: const [OpenAiRealtimeAsrStrategy(), MockTaigiAsrStrategy()],
      ),
    );
    final conversationController = ConversationController(
      profileController: profileController,
      petController: petController,
      toolRouter: toolRouter,
      ttsService: ttsService ?? TextToSpeechService(),
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
      localStorage: localStorage,
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

class _DeferredGreetingMemoryService extends MemoryService {
  final Completer<String?> _greeting = Completer<String?>();
  bool requested = false;

  @override
  Future<String?> getGreeting({
    required String userId,
    required String petName,
    required int localHour,
  }) {
    requested = true;
    return _greeting.future;
  }

  void complete(String greeting) {
    if (!_greeting.isCompleted) _greeting.complete(greeting);
  }
}
