import 'package:url_launcher/url_launcher.dart';

import '../controllers/app_navigation_controller.dart';
import '../controllers/memory_controller.dart';
import '../controllers/reminder_controller.dart';
import '../models/agent_tool_execution_result.dart';
import '../models/agent_tool_intent.dart';
import '../routes/app_routes.dart';
import 'search_service.dart';

typedef UrlLauncherCallback = Future<bool> Function(
  Uri uri,
  LaunchMode mode,
);

class NativeToolExecutorService {
  NativeToolExecutorService({
    UrlLauncherCallback? launch,
  }) : _launch = launch ?? _defaultLaunch;

  final UrlLauncherCallback _launch;

  static const Set<String> supportedToolNames = {
    'play_music',
    'open_phone_dialer',
    'create_email_draft',
    'create_reminder',
    'search_trusted_info',
    'open_app_route',
    'save_memory',
    'retrieve_memory',
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
        'create_email_draft' => _createEmailDraft(intent),
        'create_reminder' => _createReminder(intent, reminderController),
        'search_trusted_info' => _searchTrustedInfo(intent, searchService),
        'open_app_route' => _openAppRoute(intent, navigationController),
        'save_memory' => _saveMemory(intent, memoryController),
        'retrieve_memory' => _retrieveMemory(intent, memoryController),
        _ => Future.value(AgentToolExecutionResult.failed(
            toolName: intent.toolName,
            message: '不支援的工具，已拒絕執行。',
          )),
      };
    } catch (error) {
      return AgentToolExecutionResult.failed(
        toolName: intent.toolName,
        message: '工具執行失敗：$error',
      );
    }
  }

  Future<AgentToolExecutionResult> _playMusic(AgentToolIntent intent) async {
    final query = _stringArg(intent, 'query', fallback: '放鬆音樂');
    final uri = Uri.https('www.youtube.com', '/results', {
      'search_query': query,
    });
    final ok = await _launch(uri, LaunchMode.externalApplication);
    return ok
        ? AgentToolExecutionResult.succeeded(
            toolName: intent.toolName,
            message: '已開啟 YouTube 音樂搜尋。',
          )
        : AgentToolExecutionResult.failed(
            toolName: intent.toolName,
            message: '目前無法開啟音樂搜尋。',
          );
  }

  Future<AgentToolExecutionResult> _openPhoneDialer(
    AgentToolIntent intent,
  ) async {
    final phoneNumber = _stringArg(intent, 'phoneNumber');
    final uri = Uri(scheme: 'tel', path: phoneNumber);
    final ok = await _launch(uri, LaunchMode.externalApplication);
    return ok
        ? AgentToolExecutionResult.succeeded(
            toolName: intent.toolName,
            message: '已開啟撥號畫面，電話不會自動撥出。',
          )
        : AgentToolExecutionResult.failed(
            toolName: intent.toolName,
            message: '目前無法開啟撥號畫面。',
          );
  }

  Future<AgentToolExecutionResult> _createEmailDraft(
    AgentToolIntent intent,
  ) async {
    final to = _stringArg(intent, 'to');
    final subject = _stringArg(intent, 'subject', fallback: '想跟你說');
    final body = _stringArg(intent, 'body');
    final uri = Uri(
      scheme: 'mailto',
      path: to,
      queryParameters: {
        'subject': subject,
        if (body.isNotEmpty) 'body': body,
      },
    );
    final ok = await _launch(uri, LaunchMode.externalApplication);
    return ok
        ? AgentToolExecutionResult.succeeded(
            toolName: intent.toolName,
            message: '已建立 Email 草稿，信件不會自動寄出。',
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
    return AgentToolExecutionResult.succeeded(
      toolName: intent.toolName,
      message: result.summary.isNotEmpty ? result.summary : result.answer,
      data: {
        'answer': result.answer,
        'sources': result.sources.map((source) => source.toJson()).toList(),
      },
    );
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
      AppRoute.history => AppRoute.history,
      AppRoute.settings => AppRoute.settings,
      AppRoute.reminders => AppRoute.reminders,
      AppRoute.memories => AppRoute.memories,
      _ => AppRoute.home,
    };
  }

  static Future<bool> _defaultLaunch(Uri uri, LaunchMode mode) {
    return launchUrl(uri, mode: mode);
  }
}
