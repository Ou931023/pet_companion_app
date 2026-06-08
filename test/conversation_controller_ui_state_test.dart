import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pet_companion_app/models/conversation_turn.dart';
import 'package:pet_companion_app/screens/conversation_detail_screen.dart';
import 'package:pet_companion_app/screens/history_screen.dart';
import 'package:pet_companion_app/services/conversation_title_service.dart';
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
import 'package:pet_companion_app/models/taigi_asr_result.dart';
import 'package:pet_companion_app/models/taigi_asr_status.dart';

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

    test('Taigi ASR transcript waits for confirmation before history',
        () async {
      await controller.profileController.setTtsEnabled(false);
      final fakeService = _FakeTaigiAsrService(
        result: const TaigiAsrResult(
          success: true,
          transcript: '今仔日心情無好',
          language: 'taigi',
          confidence: 0,
          source: 'taigi-asr',
          durationMs: 1200,
        ),
      );
      final controllerWithFake = _createConversationController(
        taigiAsrService: fakeService,
      );
      addTearDown(controllerWithFake.dispose);
      await controllerWithFake.profileController.setTtsEnabled(false);

      expect(await controllerWithFake.startTaigiShortRecording(), isTrue);
      await controllerWithFake.stopTaigiShortRecordingAndTranscribe();

      expect(controllerWithFake.history, isEmpty);
      expect(controllerWithFake.pendingTaigiAsrTranscript, '今仔日心情無好');
      expect(controllerWithFake.taigiAsrStatusMessage, '請確認辨識內容');
    });

    test('confirming pending Taigi ASR transcript stores source metadata',
        () async {
      await controller.profileController.setTtsEnabled(false);
      final fakeService = _FakeTaigiAsrService(
        result: const TaigiAsrResult(
          success: true,
          transcript: '今仔日心情無好',
          language: 'taigi',
          confidence: 0,
          source: 'taigi-asr',
          durationMs: 1200,
        ),
      );
      final controllerWithFake = _createConversationController(
        taigiAsrService: fakeService,
      );
      addTearDown(controllerWithFake.dispose);
      await controllerWithFake.profileController.setTtsEnabled(false);

      await controllerWithFake.startTaigiShortRecording();
      await controllerWithFake.stopTaigiShortRecordingAndTranscribe();
      await controllerWithFake.confirmPendingTaigiAsrTranscript();

      expect(controllerWithFake.pendingTaigiAsrTranscript, isEmpty);
      expect(controllerWithFake.history.first.userText, '今仔日心情無好');
      expect(controllerWithFake.history.first.languageHint, 'taigi');
      expect(controllerWithFake.history.first.asrSource, 'taigi-asr');
      expect(
        controllerWithFake.history.first.routeReason,
        'taigi_asr_transcript',
      );
      expect(controllerWithFake.history.first.replyLanguage, 'mixed-zh-taigi');
    });

    test('retry clears pending Taigi ASR transcript', () async {
      controller.clearPendingTaigiAsrTranscript();
      final fakeService = _FakeTaigiAsrService(
        result: const TaigiAsrResult(
          success: true,
          transcript: '食飽未',
          language: 'taigi',
          confidence: 0,
          source: 'taigi-asr',
          durationMs: 900,
        ),
      );
      final controllerWithFake = _createConversationController(
        taigiAsrService: fakeService,
      );
      addTearDown(controllerWithFake.dispose);

      await controllerWithFake.startTaigiShortRecording();
      await controllerWithFake.stopTaigiShortRecordingAndTranscribe();
      controllerWithFake.clearPendingTaigiAsrTranscript();

      expect(controllerWithFake.pendingTaigiAsrTranscript, isEmpty);
      expect(controllerWithFake.history, isEmpty);
    });

    test('empty Taigi ASR result does not add history', () async {
      final fakeService = _FakeTaigiAsrService(
        result: TaigiAsrResult.empty(),
      );
      final controllerWithFake = _createConversationController(
        taigiAsrService: fakeService,
      );
      addTearDown(controllerWithFake.dispose);

      await controllerWithFake.startTaigiShortRecording();
      await controllerWithFake.stopTaigiShortRecordingAndTranscribe();

      expect(controllerWithFake.pendingTaigiAsrTranscript, isEmpty);
      expect(controllerWithFake.history, isEmpty);
      expect(
        controllerWithFake.taigiAsrStatusMessage,
        '我這次沒有聽清楚，可以再說一次嗎？',
      );
    });

    test('Realtime busy state blocks Taigi short recording', () async {
      final started = await controller.startTaigiShortRecording(
        realtimeBusy: true,
      );

      expect(started, isFalse);
      expect(controller.isTaigiAsrRecording, isFalse);
      expect(controller.taigiAsrStatusMessage, '請先結束目前語音對話。');
    });

    test('unavailable Taigi ASR status blocks short recording', () async {
      final controllerWithFake = _createConversationController(
        taigiAsrService: _FakeTaigiAsrService(
          result: TaigiAsrResult.empty(),
          status: TaigiAsrStatus.unavailable(),
        ),
      );
      addTearDown(controllerWithFake.dispose);

      final started = await controllerWithFake.startTaigiShortRecording();

      expect(started, isFalse);
      expect(controllerWithFake.isTaigiAsrRecording, isFalse);
      expect(
        controllerWithFake.taigiAsrStatusMessage,
        '台語語音辨識暫時無法使用',
      );
    });
  });

  group('刪除單筆對話紀錄（CR-0021）', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    ConversationTurn makeTurn(
            String sid, DateTime ts, String user, String pet) =>
        ConversationTurn(
          timestamp: ts,
          userText: user,
          petReply: pet,
          toolName: '',
          sessionId: sid,
        );

    test('只移除指定那一筆，其他訊息不受影響', () async {
      final controller = _createConversationController();
      addTearDown(controller.dispose);
      controller.startNewSession();
      final sid = controller.activeSessionId;
      controller.appendExternalTurn(makeTurn(sid, DateTime(2026, 1, 1), '第一句', '回一'));
      controller.appendExternalTurn(makeTurn(sid, DateTime(2026, 1, 2), '第二句', '回二'));
      controller.appendExternalTurn(makeTurn(sid, DateTime(2026, 1, 3), '第三句', '回三'));
      expect(controller.turnsForSession(sid).length, 3);

      final removed =
          await controller.deleteConversationTurn(controller.turnsForSession(sid)[1]);

      expect(removed, isTrue);
      final after = controller.turnsForSession(sid);
      expect(after.length, 2);
      expect(after.map((t) => t.userText).toList(), ['第一句', '第三句']);
    });

    test('刪除不存在的紀錄回 false，歷史不變', () async {
      final controller = _createConversationController();
      addTearDown(controller.dispose);
      controller.startNewSession();
      final sid = controller.activeSessionId;
      controller.appendExternalTurn(makeTurn(sid, DateTime(2026, 1, 1), '只有一句', 'ok'));

      final ghost = makeTurn(sid, DateTime(2030, 1, 1), '不存在', '');
      final removed = await controller.deleteConversationTurn(ghost);

      expect(removed, isFalse);
      expect(controller.turnsForSession(sid).length, 1);
    });

    test('只刪一則：刪使用者那句，寵物回覆保留', () async {
      final controller = _createConversationController();
      addTearDown(controller.dispose);
      controller.startNewSession();
      final sid = controller.activeSessionId;
      controller
          .appendExternalTurn(makeTurn(sid, DateTime(2026, 1, 1), '我的話', '寵物的回覆'));

      final ok = await controller.deleteConversationMessage(
        controller.turnsForSession(sid).first,
        deleteUser: true,
      );

      expect(ok, isTrue);
      final after = controller.turnsForSession(sid);
      expect(after.length, 1, reason: '整段還在，只是少了使用者那句');
      expect(after.first.userText, '');
      expect(after.first.petReply, '寵物的回覆');
    });

    test('只刪一則：刪寵物那句，使用者那句保留', () async {
      final controller = _createConversationController();
      addTearDown(controller.dispose);
      controller.startNewSession();
      final sid = controller.activeSessionId;
      controller
          .appendExternalTurn(makeTurn(sid, DateTime(2026, 1, 1), '我的話', '寵物的回覆'));

      final ok = await controller.deleteConversationMessage(
        controller.turnsForSession(sid).first,
        deleteUser: false,
      );

      expect(ok, isTrue);
      final after = controller.turnsForSession(sid);
      expect(after.length, 1);
      expect(after.first.userText, '我的話');
      expect(after.first.petReply, '');
    });

    test('只刪一則：兩側都空了 → 整段移除', () async {
      final controller = _createConversationController();
      addTearDown(controller.dispose);
      controller.startNewSession();
      final sid = controller.activeSessionId;
      controller
          .appendExternalTurn(makeTurn(sid, DateTime(2026, 1, 1), '只有我這句', ''));

      final ok = await controller.deleteConversationMessage(
        controller.turnsForSession(sid).first,
        deleteUser: true,
      );

      expect(ok, isTrue);
      expect(controller.turnsForSession(sid), isEmpty);
    });

    test('只刪一則：找不到該筆回 false', () async {
      final controller = _createConversationController();
      addTearDown(controller.dispose);
      controller.startNewSession();
      final sid = controller.activeSessionId;
      controller.appendExternalTurn(makeTurn(sid, DateTime(2026, 1, 1), 'A', 'B'));

      final ghost = makeTurn(sid, DateTime(2030, 1, 1), '不存在', '');
      final ok = await controller.deleteConversationMessage(ghost, deleteUser: true);

      expect(ok, isFalse);
      expect(controller.turnsForSession(sid).length, 1);
    });

    testWidgets('長按使用者泡泡 → 只刪那一句，寵物回覆與其他訊息保留', (tester) async {
      final controller = _createConversationController();
      addTearDown(controller.dispose);
      controller.startNewSession();
      final sid = controller.activeSessionId;
      controller.appendExternalTurn(
          makeTurn(sid, DateTime(2026, 1, 1), '想刪的訊息', '對應的回覆'));
      controller.appendExternalTurn(makeTurn(sid, DateTime(2026, 1, 2), '保留的訊息', 'B'));

      await tester.pumpWidget(
        ChangeNotifierProvider<ConversationController>.value(
          value: controller,
          child: MaterialApp(
            home: ConversationDetailScreen(sessionId: sid, title: '紀錄'),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('想刪的訊息'), findsOneWidget);
      expect(find.text('對應的回覆'), findsOneWidget);

      // 長按使用者泡泡 → 出現「只刪這一句」確認視窗。
      await tester.longPress(find.text('想刪的訊息'));
      await tester.pumpAndSettle();
      expect(find.text('要刪掉這一句嗎？'), findsOneWidget);

      // 取消 → 不刪。
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('想刪的訊息'), findsOneWidget);

      // 再長按 → 刪除 → 只移除使用者那句，寵物回覆與其他訊息都還在。
      await tester.longPress(find.text('想刪的訊息'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('刪除'));
      await tester.pumpAndSettle();
      expect(find.text('想刪的訊息'), findsNothing);
      expect(find.text('對應的回覆'), findsOneWidget);
      expect(find.text('保留的訊息'), findsOneWidget);
    });

    testWidgets('長按情緒列 → 刪整段（使用者與寵物兩句一起移除）', (tester) async {
      final controller = _createConversationController();
      addTearDown(controller.dispose);
      controller.startNewSession();
      final sid = controller.activeSessionId;
      controller
          .appendExternalTurn(makeTurn(sid, DateTime(2026, 1, 1), '整段想刪', '一起刪'));
      controller.appendExternalTurn(makeTurn(sid, DateTime(2026, 1, 2), '保留的訊息', 'B'));

      await tester.pumpWidget(
        ChangeNotifierProvider<ConversationController>.value(
          value: controller,
          child: MaterialApp(
            home: ConversationDetailScreen(sessionId: sid, title: '紀錄'),
          ),
        ),
      );
      await tester.pump();

      // 長按情緒列（含「長按這行刪整段」）→ 出現刪整段確認。
      await tester.longPress(
        find.text('情緒：neutral｜寵物心情：neutral　·　長按這行刪整段').first,
      );
      await tester.pumpAndSettle();
      expect(find.text('要刪除整段對話嗎？'), findsOneWidget);

      await tester.tap(find.text('刪除'));
      await tester.pumpAndSettle();
      expect(find.text('整段想刪'), findsNothing);
      expect(find.text('一起刪'), findsNothing);
      expect(find.text('保留的訊息'), findsOneWidget);
    });
  });

  group('對話紀錄標題與刪除（CR-0027）', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    ConversationTurn makeTurn(
            String sid, DateTime ts, String user, String pet,
            {String emotion = 'neutral'}) =>
        ConversationTurn(
          timestamp: ts,
          userText: user,
          petReply: pet,
          toolName: '',
          sessionId: sid,
          emotionTag: emotion,
        );

    test('有 LLM 標題時，列表顯示該標題', () async {
      final controller = _createConversationController(
        titleService: const _FakeTitleService('睡不好與孤單感'),
      );
      addTearDown(controller.dispose);
      controller.startNewSession();
      final sid = controller.activeSessionId;
      controller.appendExternalTurn(
          makeTurn(sid, DateTime(2026, 1, 1), '我覺得很累，又睡不著，常常一個人', '我陪你'));

      await controller.ensureSessionTitles();

      expect(controller.sessionSummaries.first.title, '睡不好與孤單感');
    });

    test('沒有標題時，從第一則使用者訊息產生 fallback 標題', () async {
      final controller =
          _createConversationController(titleService: const _FakeTitleService(null));
      addTearDown(controller.dispose);
      controller.startNewSession();
      final sid = controller.activeSessionId;
      controller
          .appendExternalTurn(makeTurn(sid, DateTime(2026, 1, 1), '我想聽音樂', '好啊'));

      expect(controller.sessionSummaries.first.title, '我想聽音樂');
    });

    test('長句 fallback 會被整理成 ≤14 字短標題', () async {
      final controller =
          _createConversationController(titleService: const _FakeTitleService(null));
      addTearDown(controller.dispose);
      controller.startNewSession();
      final sid = controller.activeSessionId;
      controller.appendExternalTurn(makeTurn(sid, DateTime(2026, 1, 1),
          '我今天去公園散步又買菜還煮了晚餐然後看了電視覺得有點累', '辛苦了'));

      final title = controller.sessionSummaries.first.title;
      expect(title.runes.length, lessThanOrEqualTo(14));
      expect(title, isNot(contains('未命名')));
    });

    test('完全沒有內容時顯示「未命名對話」', () async {
      final controller =
          _createConversationController(titleService: const _FakeTitleService(null));
      addTearDown(controller.dispose);
      controller.startNewSession();
      final sid = controller.activeSessionId;
      controller.appendExternalTurn(makeTurn(sid, DateTime(2026, 1, 1), '', ''));

      expect(controller.sessionSummaries.first.title, '未命名對話');
    });

    test('標題不含英文 mood label，也不含「情緒：」「寵物心情：」metadata', () async {
      final controller =
          _createConversationController(titleService: const _FakeTitleService(null));
      addTearDown(controller.dispose);
      controller.startNewSession();
      final sid = controller.activeSessionId;
      controller.appendExternalTurn(makeTurn(
          sid, DateTime(2026, 1, 1), '我想出去走走', '好啊',
          emotion: 'lonely'));

      final title = controller.sessionSummaries.first.title;
      expect(title.contains('lonely'), isFalse);
      expect(title.contains('neutral'), isFalse);
      expect(title.contains('情緒：'), isFalse);
      expect(title.contains('寵物心情：'), isFalse);
    });

    test('刪除一則 session：只移除該則，其他保留', () async {
      final controller =
          _createConversationController(titleService: const _FakeTitleService(null));
      addTearDown(controller.dispose);
      controller.startNewSession();
      final a = controller.activeSessionId;
      controller.appendExternalTurn(makeTurn(a, DateTime(2026, 1, 1), 'A第一', 'a'));
      controller.appendExternalTurn(makeTurn(a, DateTime(2026, 1, 2), 'A第二', 'a2'));
      controller.startNewSession();
      final b = controller.activeSessionId;
      controller.appendExternalTurn(makeTurn(b, DateTime(2026, 1, 3), 'B第一', 'b'));

      final ok = await controller.deleteConversationSession(a);

      expect(ok, isTrue);
      expect(controller.turnsForSession(a), isEmpty);
      expect(controller.turnsForSession(b).length, 1);
      expect(controller.sessionSummaries.length, 1);
    });

    test('刪除不存在的 session 回 false', () async {
      final controller =
          _createConversationController(titleService: const _FakeTitleService(null));
      addTearDown(controller.dispose);
      controller.startNewSession();
      final sid = controller.activeSessionId;
      controller.appendExternalTurn(makeTurn(sid, DateTime(2026, 1, 1), '在', 'ok'));

      final ok = await controller.deleteConversationSession('no_such_session');

      expect(ok, isFalse);
      expect(controller.turnsForSession(sid).length, 1);
    });

    testWidgets('長按列表卡片 → 確認視窗；取消不刪；刪除只移除該則', (tester) async {
      final controller =
          _createConversationController(titleService: const _FakeTitleService(null));
      addTearDown(controller.dispose);
      controller.startNewSession();
      final a = controller.activeSessionId;
      controller.appendExternalTurn(makeTurn(a, DateTime(2026, 1, 1), '想刪的對話', 'x'));
      controller.startNewSession();
      final b = controller.activeSessionId;
      controller.appendExternalTurn(makeTurn(b, DateTime(2026, 1, 2), '保留的對話', 'y'));

      await tester.pumpWidget(
        ChangeNotifierProvider<ConversationController>.value(
          value: controller,
          child: const MaterialApp(home: Scaffold(body: HistoryScreen())),
        ),
      );
      await tester.pump();
      expect(find.text('想刪的對話'), findsOneWidget);
      expect(find.text('保留的對話'), findsOneWidget);

      // 長按卡片 → 出現刪除確認（不直接刪）。
      await tester.longPress(find.text('想刪的對話'));
      await tester.pumpAndSettle();
      expect(find.text('刪除這則對話？'), findsOneWidget);

      // 取消 → 不刪。
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('想刪的對話'), findsOneWidget);

      // 再長按 → 刪除 → 只移除該則，其他保留。
      await tester.longPress(find.text('想刪的對話'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('刪除'));
      await tester.pumpAndSettle();
      expect(find.text('想刪的對話'), findsNothing);
      expect(find.text('保留的對話'), findsOneWidget);
    });
  });
}

/// 測試用假標題服務：回傳預設標題（或 null 走 fallback），不打網路。
class _FakeTitleService extends ConversationTitleService {
  const _FakeTitleService(this._title);

  final String? _title;

  @override
  Future<String?> generateTitle({
    required String firstUserText,
    required String conversationText,
  }) async =>
      _title;
}

ConversationController _createConversationController({
  TaigiAsrService? taigiAsrService,
  ConversationTitleService? titleService,
}) {
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
    sttService: MockSpeechToTextService(),
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
    taigiAsrService: taigiAsrService ?? TaigiAsrService(),
    titleService: titleService ?? const ConversationTitleService(),
  );
}

class _FakeTaigiAsrService extends TaigiAsrService {
  _FakeTaigiAsrService({
    required this.result,
    this.status = const TaigiAsrStatus(
      enabled: true,
      available: true,
      warmingUp: false,
      modelReady: false,
      message: 'Taigi ASR is available',
    ),
  });

  final TaigiAsrResult result;
  final TaigiAsrStatus status;
  File? _file;

  @override
  Future<TaigiAsrStatus> fetchStatus({
    required String sttProxyUrl,
  }) async {
    return status;
  }

  @override
  Future<void> startRecording() async {
    final dir = await Directory.systemTemp.createTemp('fake_taigi_asr_');
    _file = File('${dir.path}/sample.m4a');
    await _file!.writeAsBytes([0, 1, 2, 3]);
  }

  @override
  Future<File?> stopRecording() async => _file;

  @override
  Future<TaigiAsrResult> transcribeAudio({
    required File audioFile,
    required String sttProxyUrl,
  }) async {
    return result;
  }
}
