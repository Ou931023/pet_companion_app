import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controllers/app_navigation_controller.dart';
import '../controllers/memory_controller.dart';
import '../controllers/reminder_controller.dart';
import '../models/agent_tool_execution_result.dart';
import '../models/agent_tool_intent.dart';
import '../routes/app_routes.dart';
import 'contact_lookup_service.dart';
import 'search_service.dart';

typedef UrlLauncherCallback = Future<bool> Function(
  Uri uri,
  LaunchMode mode,
);

/// 需要跨子系統（Auth / Shop / Care Alert / 內容）的高影響工具，透過 optional callback
/// 注入「既有真實流程」，讓 Native Tool 執行層與那些控制器解耦、且方便單元測試。
/// 這些 callback 對應的工具都是 requiresConfirmation=true，只有在使用者確認後才會被呼叫。
typedef AgentLogoutCallback = Future<void> Function();
typedef AgentNotifyCaregiverCallback = Future<bool> Function({
  required String reason,
  required String riskLevel,
});
typedef AgentPurchaseSkinCallback = Future<bool> Function({
  required String skinId,
  required String skinName,
});
typedef AgentStoryProvider = Future<String> Function(String topic);

class NativeToolExecutorService {
  NativeToolExecutorService({
    UrlLauncherCallback? launch,
    this.contactLookup,
    this.onLogout,
    this.onNotifyCaregiver,
    this.onPurchaseSkin,
    this.storyProvider,
  }) : _launch = launch ?? _defaultLaunch;

  final UrlLauncherCallback _launch;
  final ContactLookupService? contactLookup;
  final AgentLogoutCallback? onLogout;
  final AgentNotifyCaregiverCallback? onNotifyCaregiver;
  final AgentPurchaseSkinCallback? onPurchaseSkin;
  final AgentStoryProvider? storyProvider;

  static const Set<String> supportedToolNames = {
    'play_music',
    'open_phone_dialer',
    'send_message',
    'create_email_draft',
    'create_reminder',
    'search_trusted_info',
    'open_app_route',
    'tell_story',
    'save_memory',
    'retrieve_memory',
    'notify_caregiver',
    'delete_memory',
    'logout',
    'purchase_pet_skin',
  };

  Future<AgentToolExecutionResult> execute({
    required AgentToolIntent intent,
    required ReminderController reminderController,
    required SearchService searchService,
    required AppNavigationController navigationController,
    required MemoryController memoryController,
  }) async {
    if (!supportedToolNames.contains(intent.toolName)) {
      return AgentToolExecutionResult.failed(
        toolName: intent.toolName,
        message: '不支援的工具，已拒絕執行。',
      );
    }
    try {
      return await switch (intent.toolName) {
        'play_music' => _playMusic(intent),
        'open_phone_dialer' => _openPhoneDialer(intent),
        'send_message' => _sendMessage(intent),
        'create_email_draft' => _createEmailDraft(intent),
        'create_reminder' => _createReminder(intent, reminderController),
        'search_trusted_info' => _searchTrustedInfo(intent, searchService),
        'open_app_route' => _openAppRoute(intent, navigationController),
        'tell_story' => _tellStory(intent),
        'save_memory' => _saveMemory(intent, memoryController),
        'retrieve_memory' => _retrieveMemory(intent, memoryController),
        'notify_caregiver' => _notifyCaregiver(intent),
        'delete_memory' => _deleteMemory(intent, memoryController),
        'logout' => _logout(intent),
        'purchase_pet_skin' => _purchaseSkin(intent),
        _ => Future.value(AgentToolExecutionResult.failed(
            toolName: intent.toolName,
            message: '不支援的工具，已拒絕執行。',
          )),
      };
    } catch (error, stackTrace) {
      // 原始錯誤只留給開發者除錯，絕不顯示給長者。
      debugPrint(
          '[NativeToolExecutorService] ${intent.toolName} failed: $error\n$stackTrace');
      return AgentToolExecutionResult.failed(
        toolName: intent.toolName,
        message: '這個動作暫時沒辦法完成，待會再試一次好嗎？',
      );
    }
  }

  /// 長者說「播放音樂」時要真的「開始播放」，而不是只丟一頁 YouTube 搜尋結果讓他自己找。
  /// 依長者講的類型對應到精選、長輩友善、無廣告的 YouTube 影片（開 watch 連結，
  /// iOS 會交給 YouTube App 直接播放）。認不得的查詢（指定歌手 / 歌名等）才退回搜尋。
  ///
  /// 影片來源（皆為公開、可用、無廣告長片，2026-06 驗證可播）：
  /// - 放鬆 / 輕音樂：「放鬆音樂 - Relaxing Music Sleep」高品質放鬆輕音樂。
  /// - 台語老歌：「懷舊台語老歌金曲」雨夜花 / 望春風 / 港都夜雨。
  /// - 白噪音 / 助眠：「自然音樂」樹林雨聲雷聲助眠白噪音。
  static const String _relaxingMusicVideoId = 'Qes9vypXOlE';
  static const String _taiwaneseOldiesVideoId = 'aRrXwHP0v4A';
  static const String _whiteNoiseVideoId = '-ERFwSSqg1Y';

  /// 由 backend agent（extractMusicQuery）帶來的 query 或長者口語，判斷要播哪一類。
  /// 認不得 → 回 null，由呼叫端退回 YouTube 搜尋（保留任意歌手 / 歌名仍可查的能力）。
  static String? _curatedMusicVideoIdFor(String query) {
    bool hasAny(List<String> keywords) =>
        keywords.any((keyword) => query.contains(keyword));

    // 先比對較專一的類別，避免被通用詞搶走。
    if (hasAny(['台語', '老歌', '懷舊', '望春風', '雨夜花', '港都'])) {
      return _taiwaneseOldiesVideoId;
    }
    if (hasAny(['白噪音', '雨聲', '海浪', '助眠', '入睡', 'asmr', '睡覺', '睏'])) {
      return _whiteNoiseVideoId;
    }
    if (hasAny(['放鬆', '輕音樂', '療癒', '冥想', '紓壓', '舒壓', '放空'])) {
      return _relaxingMusicVideoId;
    }
    return null;
  }

  Future<AgentToolExecutionResult> _playMusic(AgentToolIntent intent) async {
    final query = _stringArg(intent, 'query', fallback: '放鬆音樂');
    final videoId = _curatedMusicVideoIdFor(query);
    final isPlayback = videoId != null;
    final uri = isPlayback
        ? Uri.https('www.youtube.com', '/watch', {'v': videoId})
        : Uri.https('www.youtube.com', '/results', {'search_query': query});
    final ok = await _launch(uri, LaunchMode.externalApplication);
    return ok
        ? AgentToolExecutionResult.succeeded(
            toolName: intent.toolName,
            message: isPlayback ? '好的，幫你播放音樂了。' : '已開啟 YouTube 音樂搜尋。',
          )
        : AgentToolExecutionResult.failed(
            toolName: intent.toolName,
            message: '目前無法開啟音樂。',
          );
  }

  Future<AgentToolExecutionResult> _openPhoneDialer(
    AgentToolIntent intent,
  ) async {
    var phoneNumber = _stringArg(intent, 'phoneNumber');
    if (phoneNumber.isEmpty && contactLookup != null) {
      final contactName = _stringArg(intent, 'contactName');
      if (contactName.isNotEmpty) {
        final resolved = await contactLookup!.lookupPhoneNumber(contactName);
        if (resolved != null && resolved.isNotEmpty) {
          phoneNumber = resolved;
        }
      }
    }
    final uri = Uri(scheme: 'tel', path: phoneNumber);
    final ok = await _launch(uri, LaunchMode.externalApplication);
    return ok
        ? AgentToolExecutionResult.succeeded(
            toolName: intent.toolName,
            message:
                phoneNumber.isEmpty ? '已開啟撥號畫面，請輸入號碼。' : '已撥號到 $phoneNumber。',
          )
        : AgentToolExecutionResult.failed(
            toolName: intent.toolName,
            message: '目前無法開啟撥號畫面。',
          );
  }

  /// 傳訊息：開啟系統簡訊 App 並預填收件人與內容，**不自動送出**（使用者在簡訊
  /// App 內再按送出）。此工具 requiresConfirmation=true，已在確認後才到這裡。
  Future<AgentToolExecutionResult> _sendMessage(AgentToolIntent intent) async {
    var phoneNumber = _stringArg(intent, 'phoneNumber');
    if (phoneNumber.isEmpty && contactLookup != null) {
      final contactName = _stringArg(intent, 'contactName',
          fallback: _stringArg(intent, 'recipient'));
      if (contactName.isNotEmpty) {
        final resolved = await contactLookup!.lookupPhoneNumber(contactName);
        if (resolved != null && resolved.isNotEmpty) phoneNumber = resolved;
      }
    }
    final body = _stringArg(intent, 'body');
    final uri = Uri(
      scheme: 'sms',
      path: phoneNumber,
      queryParameters: body.isEmpty ? null : {'body': body},
    );
    final ok = await _launch(uri, LaunchMode.externalApplication);
    return ok
        ? AgentToolExecutionResult.succeeded(
            toolName: intent.toolName,
            message: phoneNumber.isEmpty
                ? '已幫你開啟訊息，請選擇收件人再送出。'
                : '已幫你準備好訊息，確認後再送出就可以了。',
            data: {'body': body},
          )
        : AgentToolExecutionResult.failed(
            toolName: intent.toolName,
            message: '目前無法開啟訊息。',
          );
  }

  Future<AgentToolExecutionResult> _createEmailDraft(
    AgentToolIntent intent,
  ) async {
    var to = _stringArg(intent, 'to');
    // The `to` field from the LLM can be a Chinese alias like 「家人」; resolve
    // it to a real email through the in-app family contacts table.
    if ((to.isEmpty || !to.contains('@')) && contactLookup != null) {
      final resolved = await contactLookup!.lookupEmail(to);
      if (resolved != null && resolved.isNotEmpty) to = resolved;
    }
    final subject = _stringArg(intent, 'subject', fallback: '想跟你說');
    final body = _stringArg(intent, 'body');
    final uri = Uri(
      scheme: 'mailto',
      path: to.contains('@') ? to : '',
      queryParameters: {
        'subject': subject,
        if (body.isNotEmpty) 'body': body,
      },
    );
    final ok = await _launch(uri, LaunchMode.externalApplication);
    return ok
        ? AgentToolExecutionResult.succeeded(
            toolName: intent.toolName,
            message:
                to.contains('@') ? '已建立 Email 草稿，收件人 $to。' : '已開啟郵件，請輸入收件人。',
          )
        : AgentToolExecutionResult.failed(
            toolName: intent.toolName,
            message: '目前無法開啟 Email 草稿。',
          );
  }

  Future<AgentToolExecutionResult> _createReminder(
    AgentToolIntent intent,
    ReminderController reminderController,
  ) async {
    final text = _stringArg(intent, 'text', fallback: intent.userFacingMessage);
    final reminder = await reminderController.createFromVoice(text);
    if (reminder == null) {
      return AgentToolExecutionResult.failed(
        toolName: intent.toolName,
        message: '我還無法判斷提醒時間，請再說一次時間。',
      );
    }
    return AgentToolExecutionResult.succeeded(
      toolName: intent.toolName,
      message: '已建立提醒：${reminder.timeLabel}${reminder.title}',
      data: {'reminderId': reminder.id},
    );
  }

  Future<AgentToolExecutionResult> _searchTrustedInfo(
    AgentToolIntent intent,
    SearchService searchService,
  ) async {
    final query =
        _stringArg(intent, 'query', fallback: intent.userFacingMessage);
    final result = await searchService.search(query);
    final message = _conciseSearchMessage(
      query: query,
      summary: result.summary,
      answer: result.answer,
    );
    return AgentToolExecutionResult.succeeded(
      toolName: intent.toolName,
      message: message,
      data: {
        'answer': result.answer,
        'sources': result.sources.map((source) => source.toJson()).toList(),
      },
    );
  }

  static String _conciseSearchMessage({
    required String query,
    required String summary,
    required String answer,
  }) {
    final raw = (summary.trim().isNotEmpty ? summary : answer).trim();
    if (raw.isEmpty) return '我查到的資料不多，晚點再幫你確認一次。';
    final normalized = raw.replaceAll(RegExp(r'\s+'), ' ');
    final maxLength = _isNewsQuery(query) ? 120 : 180;
    final clipped = normalized.length > maxLength
        ? '${normalized.substring(0, maxLength)}...'
        : normalized;
    if (!_isNewsQuery(query)) return clipped;
    if (clipped.contains('要不要') || clipped.contains('想聽')) {
      return clipped;
    }
    return '$clipped 要不要聽其中一則詳細一點？';
  }

  static bool _isNewsQuery(String text) {
    return RegExp(r'新聞|消息|防詐|詐騙').hasMatch(text);
  }

  Future<AgentToolExecutionResult> _openAppRoute(
    AgentToolIntent intent,
    AppNavigationController navigationController,
  ) async {
    final route = _normalizeRoute(_stringArg(intent, 'route'));
    navigationController.navigateTo(route);
    return AgentToolExecutionResult.succeeded(
      toolName: intent.toolName,
      message: '已切換到指定頁面。',
      data: {'route': route},
    );
  }

  Future<AgentToolExecutionResult> _saveMemory(
    AgentToolIntent intent,
    MemoryController memoryController,
  ) async {
    final memoryText = _stringArg(intent, 'memoryText');
    if (memoryText.isEmpty) {
      return AgentToolExecutionResult.failed(
        toolName: intent.toolName,
        message: '沒有可保存的記憶內容。',
      );
    }
    await memoryController.extractMemory(
      sessionId: 'agent_tool',
      turnId: intent.id,
      userText: memoryText,
      aiReply: '使用者確認保存此記憶。',
      emotion: 'neutral',
    );
    return AgentToolExecutionResult.succeeded(
      toolName: intent.toolName,
      message: '我已經試著幫你記住這件事。',
    );
  }

  Future<AgentToolExecutionResult> _retrieveMemory(
    AgentToolIntent intent,
    MemoryController memoryController,
  ) async {
    final query =
        _stringArg(intent, 'query', fallback: intent.userFacingMessage);
    final context = await memoryController.buildMemoryContext(userText: query);
    final summary = context?['promptBlock']?.toString() ?? '';
    return AgentToolExecutionResult.succeeded(
      toolName: intent.toolName,
      message: summary.isEmpty ? '目前沒有找到相關記憶。' : summary,
      data: context ?? const {},
    );
  }

  /// 說故事：低風險、直接執行。沿用既有內容服務（storyProvider）；在 Realtime 語音
  /// 流程中，寵物本身也會把故事說出來，這裡回傳的文字供文字泡泡 / 字幕顯示。
  Future<AgentToolExecutionResult> _tellStory(AgentToolIntent intent) async {
    final topic = _stringArg(intent, 'topic');
    final story = storyProvider == null ? '' : await storyProvider!(topic);
    return AgentToolExecutionResult.succeeded(
      toolName: intent.toolName,
      message: story.isNotEmpty ? story : '好，我說一個小故事陪你。',
      data: {'topic': topic},
    );
  }

  /// 通知照護人員：高影響、需確認。沿用既有 Care Alert 通知流程（透過注入的
  /// onNotifyCaregiver callback，內部呼叫既有 /api/care-alerts/notify），不另開新流程。
  Future<AgentToolExecutionResult> _notifyCaregiver(
    AgentToolIntent intent,
  ) async {
    final notify = onNotifyCaregiver;
    if (notify == null) {
      return AgentToolExecutionResult.failed(
        toolName: intent.toolName,
        message: '目前無法通知照護人員，待會再試一次好嗎？',
      );
    }
    final reason = _stringArg(intent, 'reason', fallback: '長者希望聯絡照護人員');
    final riskLevel = _stringArg(intent, 'riskLevel', fallback: 'high');
    final ok = await notify(reason: reason, riskLevel: riskLevel);
    return ok
        ? AgentToolExecutionResult.succeeded(
            toolName: intent.toolName,
            message: '我已經通知照護人員了，他們會留意你的狀況。',
          )
        : AgentToolExecutionResult.failed(
            toolName: intent.toolName,
            message: '通知沒有送出去，待會再試一次好嗎？',
          );
  }

  /// 刪除記憶：高影響、需確認。沿用既有 MemoryService（forgetRecentMemory）。
  Future<AgentToolExecutionResult> _deleteMemory(
    AgentToolIntent intent,
    MemoryController memoryController,
  ) async {
    await memoryController.forgetRecentMemory();
    return AgentToolExecutionResult.succeeded(
      toolName: intent.toolName,
      message: '好，我把最近記住的那件事刪掉了。',
    );
  }

  /// 登出：高影響、需確認。沿用既有 AuthController.logout（透過注入的 onLogout）。
  Future<AgentToolExecutionResult> _logout(AgentToolIntent intent) async {
    final logout = onLogout;
    if (logout == null) {
      return AgentToolExecutionResult.failed(
        toolName: intent.toolName,
        message: '目前無法登出，待會再試一次好嗎？',
      );
    }
    await logout();
    return AgentToolExecutionResult.succeeded(
      toolName: intent.toolName,
      message: '已經幫你登出了。',
    );
  }

  /// 購買寵物造型：高影響、需確認。沿用既有錢包 / 商城流程（透過注入的 onPurchaseSkin）。
  Future<AgentToolExecutionResult> _purchaseSkin(AgentToolIntent intent) async {
    final purchase = onPurchaseSkin;
    if (purchase == null) {
      return AgentToolExecutionResult.failed(
        toolName: intent.toolName,
        message: '購買要在商城裡完成，我帶你過去看看好嗎？',
      );
    }
    final skinId = _stringArg(intent, 'skinId');
    final skinName = _stringArg(intent, 'skinName', fallback: '新造型');
    final ok = await purchase(skinId: skinId, skinName: skinName);
    return ok
        ? AgentToolExecutionResult.succeeded(
            toolName: intent.toolName,
            message: '買好囉，幫你換上$skinName。',
          )
        : AgentToolExecutionResult.failed(
            toolName: intent.toolName,
            message: '金幣好像不太夠，這個造型先幫你留著。',
          );
  }

  String _stringArg(
    AgentToolIntent intent,
    String key, {
    String fallback = '',
  }) {
    final value = intent.arguments[key];
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  String _normalizeRoute(String route) {
    return switch (route) {
      AppRoute.shop => AppRoute.shop,
      AppRoute.marketplace => AppRoute.marketplace,
      AppRoute.history => AppRoute.history,
      AppRoute.settings => AppRoute.settings,
      AppRoute.reminders => AppRoute.reminders,
      AppRoute.dailyCareTasks => AppRoute.dailyCareTasks,
      AppRoute.memories => AppRoute.memories,
      AppRoute.album => AppRoute.album,
      AppRoute.notification => AppRoute.notification,
      AppRoute.puzzle => AppRoute.puzzle,
      AppRoute.careAlerts => AppRoute.careAlerts,
      _ => AppRoute.home,
    };
  }

  static Future<bool> _defaultLaunch(Uri uri, LaunchMode mode) {
    return launchUrl(uri, mode: mode);
  }
}
