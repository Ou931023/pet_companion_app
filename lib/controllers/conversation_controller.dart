import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/conversation_session_summary.dart';
import '../models/conversation_turn.dart';
import '../models/pet_status.dart';
import '../models/source_reference.dart';
import '../services/ai_navigation_service.dart';
import '../services/ai_tool_router.dart';
import '../services/emotion_services.dart';
import '../services/local_storage_service.dart';
import '../services/mock_speech_to_text_service.dart';
import '../services/openai_speech_to_text_service.dart';
import '../services/search_service.dart';
import '../services/speech_to_text_service.dart';
import '../services/text_to_speech_service.dart';
import 'app_navigation_controller.dart';
import 'memory_controller.dart';
import 'pet_controller.dart';
import 'pet_stats_controller.dart';
import 'profile_controller.dart';
import 'reminder_controller.dart';

class ConversationController extends ChangeNotifier {
  ConversationController({
    required this.profileController,
    required this.petController,
    required this.toolRouter,
    required this.ttsService,
    required this.mockSttService,
    required this.storageService,
    required this.searchService,
    required this.petStatsController,
    required this.navigationService,
    required this.navigationController,
    required this.reminderController,
    required this.emotionFusionService,
    required this.petEmotionMapper,
    required this.memoryController,
  });

  final ProfileController profileController;
  final PetController petController;
  final AiToolRouter toolRouter;
  final TextToSpeechService ttsService;
  final MockSpeechToTextService mockSttService;
  final LocalStorageService storageService;
  final SearchService searchService;
  final PetStatsController petStatsController;
  final AiNavigationService navigationService;
  final AppNavigationController navigationController;
  final ReminderController reminderController;
  final EmotionFusionService emotionFusionService;
  final PetEmotionMapper petEmotionMapper;
  final MemoryController memoryController;

  final List<ConversationTurn> _history = [];
  String _activeSessionId = _newSessionId();
  bool _isRecording = false;
  bool _isBusy = false;
  String _latestUserText = '';
  String _latestReply = '';
  List<SourceReference> _latestSources = const [];
  bool _latestReplyIsSearch = false;
  String _latestSearchMode = '';
  String _latestSearchProvider = '';
  String _latestToolUsed = '';

  List<ConversationTurn> get history => List.unmodifiable(_history.reversed);
  List<ConversationSessionSummary> get sessionSummaries {
    final map = <String, List<ConversationTurn>>{};
    for (final turn in _history) {
      final id = turn.sessionId.isEmpty ? 'legacy' : turn.sessionId;
      map.putIfAbsent(id, () => []).add(turn);
    }
    final summaries = map.entries.map((entry) {
      final turns = entry.value;
      final firstUser = turns.firstWhere(
        (t) => t.userText.trim().isNotEmpty,
        orElse: () => turns.first,
      );
      final firstText = firstUser.userText.trim();
      final titleBase = firstText.isEmpty
          ? '語音對話'
          : firstText.substring(
              0, firstText.length > 12 ? 12 : firstText.length);
      final updatedAt = turns.last.timestamp;
      final lastPreview = turns.last.petReply.trim().isNotEmpty
          ? turns.last.petReply.trim()
          : turns.last.userText.trim();
      final emotion = turns.reversed
          .firstWhere(
            (t) => t.emotionTag != 'neutral',
            orElse: () => turns.last,
          )
          .emotionTag;
      return ConversationSessionSummary(
        sessionId: entry.key,
        title: titleBase,
        updatedAt: updatedAt,
        lastPreview: lastPreview.isEmpty ? '語音對話' : lastPreview,
        emotionTag: emotion,
      );
    }).toList();
    summaries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return summaries;
  }

  bool get isRecording => _isRecording;
  void startNewSession() {
    _activeSessionId = _newSessionId();
  }

  List<ConversationTurn> turnsForSession(String sessionId) {
    return _history
        .where(
            (t) => (t.sessionId.isEmpty ? 'legacy' : t.sessionId) == sessionId)
        .toList();
  }

  bool get isBusy => _isBusy;
  String get activeSessionId => _activeSessionId;
  String get latestUserText => _latestUserText;
  String get latestReply => _latestReply;
  List<SourceReference> get latestSources => List.unmodifiable(_latestSources);
  bool get latestReplyIsSearch => _latestReplyIsSearch;
  String get latestSearchMode => _latestSearchMode;
  String get latestSearchProvider => _latestSearchProvider;
  String get latestToolUsed => _latestToolUsed;

  Future<void> loadHistory() async {
    final turns = await storageService.loadConversationHistory();
    _history
      ..clear()
      ..addAll(turns);
    notifyListeners();
  }

  SpeechToTextService _currentSttService() {
    if (profileController.sttMode == SttMode.openAiProxy) {
      return OpenAiSpeechToTextService(proxyUrl: profileController.sttProxyUrl);
    }
    return mockSttService;
  }

  Future<void> playWelcomeGreeting() async {
    final petName = profileController.petName;
    final text = '早安，我是$petName，今天也陪你聊聊天。';
    await _deliverPetReply(text,
        petMode: PetMode.listening, toolName: 'welcome', saveToHistory: false);
  }

  Future<void> playGreeting(String text) async {
    await _deliverPetReply(
      text,
      petMode: PetMode.listening,
      toolName: 'welcome',
      saveToHistory: false,
    );
  }

  Future<void> onPressToTalkStart() async {
    _isRecording = true;
    petController.setMode(PetMode.listening);
    notifyListeners();
    if (profileController.sttMode == SttMode.openAiProxy) {
      try {
        await _currentSttService().startRecording();
      } catch (_) {
        _isRecording = false;
        notifyListeners();
        await _deliverPetReply(
          '麥克風暫時無法使用，請檢查權限後再試。',
          petMode: PetMode.sad,
          toolName: 'sttError',
        );
      }
    }
  }

  Future<void> onPressToTalkEnd({String? mockText}) async {
    _isRecording = false;
    notifyListeners();
    if (_isBusy) return;
    if (profileController.sttMode == SttMode.mock) {
      mockSttService.setNextTranscript(mockText ?? '幫我簽到');
      await _processSttResult(
        await mockSttService.transcribeAudio(File('mock.wav')),
      );
      return;
    }
    try {
      final sttService = _currentSttService();
      final audioFile = await sttService.stopRecording();
      if (audioFile == null) {
        await _deliverPetReply(
          '我剛剛沒有聽到聲音，可以再說一次嗎？',
          petMode: PetMode.listening,
          toolName: 'sttEmpty',
        );
        return;
      }
      final result = await sttService.retryTranscription(audioFile);
      await _processSttResult(result);
    } catch (_) {
      await _deliverPetReply(
        '語音辨識目前發生問題，我先切回 Mock STT，請再說一次。',
        petMode: PetMode.listening,
        toolName: 'sttError',
      );
      await profileController.setSttMode(SttMode.mock);
    }
  }

  Future<void> quickAction(String text) async {
    await _handleUserText(text);
  }

  bool shouldHandleAsLocalCommand(String text) {
    return reminderController.isCreateReminderCommand(text) ||
        reminderController.isListReminderCommand(text) ||
        toolRouter.isCompanionContentOrSearch(text);
  }

  void appendExternalTurn(ConversationTurn turn) {
    if (turn.userText.trim().isNotEmpty) {
      _latestUserText = turn.userText.trim();
    }
    _latestReplyIsSearch = turn.toolName == 'verticalSearch';
    _latestSources = turn.sources;
    _latestSearchMode = turn.searchMode;
    _latestSearchProvider = turn.searchProvider;
    _latestToolUsed = turn.toolUsed;
    _history.add(
      ConversationTurn(
        timestamp: turn.timestamp,
        userText: turn.userText,
        petReply: turn.petReply,
        toolName: turn.toolName,
        sessionId: turn.sessionId.isEmpty ? _activeSessionId : turn.sessionId,
        emotionTag: turn.emotionTag,
        petMood: turn.petMood,
        toolUsed: turn.toolUsed,
        searchMode: turn.searchMode,
        searchProvider: turn.searchProvider,
        sources: turn.sources,
      ),
    );
    unawaited(_persistHistory());
    notifyListeners();
  }

  Future<void> handleRealtimeAssistantReply(String message) async {
    _latestReply = message;
    _latestSources = const [];
    _latestReplyIsSearch = false;
    _latestSearchMode = '';
    _latestSearchProvider = '';
    _latestToolUsed = '';
    petController.setMessage(message);
    _history.add(
      ConversationTurn(
        timestamp: DateTime.now(),
        userText: _latestUserText,
        petReply: message,
        toolName: 'realtimeVoice',
        sessionId: _activeSessionId,
        petMood: petController.mood,
      ),
    );
    unawaited(_persistHistory());
    notifyListeners();
  }

  Future<void> showFallbackMessage(String message) async {
    await _deliverPetReply(
      message,
      petMode: PetMode.listening,
      toolName: 'realtimeFallback',
    );
  }

  Future<void> _processSttResult(SttResult result) async {
    if (!result.success) {
      final message = result.message ?? '我剛剛沒有聽清楚，可以再說一次嗎？';
      if (result.errorType == SttErrorType.networkError &&
          profileController.sttMode == SttMode.openAiProxy) {
        await profileController.setSttMode(SttMode.mock);
        await _deliverPetReply(
          '$message 已為你切換到 Mock STT，先確保你可以繼續使用。',
          petMode: PetMode.listening,
          toolName: 'sttFallback',
        );
        return;
      }
      await _deliverPetReply(message,
          petMode: PetMode.listening, toolName: 'sttError');
      return;
    }
    await _handleUserText(result.transcript);
  }

  Future<void> _handleUserText(String text) async {
    if (_isBusy) return;
    _isBusy = true;
    _latestUserText = text;
    notifyListeners();
    try {
      final navigationIntent = navigationService.detect(text);
      if (navigationIntent != null) {
        navigationController.navigateTo(navigationIntent.route);
        await _deliverPetReply(
          navigationIntent.reply,
          petMode: PetMode.listening,
          toolName: 'navigation',
          userText: text,
        );
        return;
      }
      final emotion = emotionFusionService.analyze(text: text);
      final emotionMode = petEmotionMapper.modeFor(emotion.emotion);
      _applyPetEmotionState(emotion.emotion, emotionMode);
      unawaited(petStatsController.applyConversationEmotion(emotion.emotion));

      if (reminderController.isCreateReminderCommand(text)) {
        final reminder = await reminderController.createFromVoice(text);
        await _deliverPetReply(
          reminder == null
              ? '我還沒聽清楚提醒時間，可以說「提醒我晚上八點吃藥」。'
              : '好，我會在${reminder.repeatLabel}${reminder.timeLabel}提醒你${reminder.title}。',
          petMode: emotionMode,
          toolName: 'createReminder',
          userText: text,
          emotionTag: emotion.emotion,
        );
        return;
      }
      if (reminderController.isListReminderCommand(text)) {
        await _deliverPetReply(
          reminderController.listSummary(),
          petMode: emotionMode,
          toolName: 'listReminders',
          userText: text,
          emotionTag: emotion.emotion,
        );
        return;
      }
      if (SearchService.shouldHandle(text)) {
        final memoryContext = await _loadMemoryContext(text);
        final searchResult = await searchService.search(text);
        final reply = searchResult.answer.trim().isEmpty
            ? '目前沒有取得可靠來源，我先不亂說，我可以先陪你聊聊或稍後再幫你查。'
            : searchResult.answer.trim();
        await _deliverPetReply(
          reply,
          petMode: emotionMode,
          toolName: 'verticalSearch',
          userText: text,
          emotionTag: emotion.emotion,
          sources: searchResult.sources,
          searchMode: searchResult.mode,
          searchProvider: searchResult.provider,
          toolUsed: searchResult.toolUsed,
          memoryUsed: memoryContext.memoryUsed,
          usedMemoryIds: memoryContext.usedMemoryIds,
          memoryContextSummary: memoryContext.memoryContextSummary,
          memoryProvider: memoryContext.memoryProvider,
        );
        return;
      }
      final memoryContext = await _loadMemoryContext(text);
      final toolResult = await toolRouter.route(
        text,
        memoryContextSummary: memoryContext.memoryContextSummary ?? '',
      );
      final petMode =
          emotion.emotion == 'neutral' ? toolResult.petMode : emotionMode;
      final comfort = petEmotionMapper.comfortPrefix(emotion.emotion);
      await _deliverPetReply(
        comfort.isEmpty ? toolResult.message : '$comfort ${toolResult.message}',
        petMode: petMode,
        toolName: toolResult.toolName,
        userText: text,
        emotionTag: emotion.emotion,
        memoryUsed: memoryContext.memoryUsed,
        usedMemoryIds: memoryContext.usedMemoryIds,
        memoryContextSummary: memoryContext.memoryContextSummary,
        memoryProvider: memoryContext.memoryProvider,
      );
    } catch (_) {
      await _deliverPetReply(
        '我剛剛有點卡住了，不過我還在這裡陪你，我們可以再說一次。',
        petMode: PetMode.caring,
        toolName: 'chatFallback',
        userText: text,
      );
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> _deliverPetReply(
    String message, {
    required PetMode petMode,
    required String toolName,
    String userText = '',
    String emotionTag = 'neutral',
    bool saveToHistory = true,
    List<SourceReference> sources = const [],
    String searchMode = '',
    String searchProvider = '',
    String toolUsed = '',
    bool memoryUsed = false,
    List<dynamic> usedMemoryIds = const [],
    String? memoryContextSummary,
    String? memoryProvider,
  }) async {
    _latestReply = message;
    _latestSources = sources;
    _latestReplyIsSearch = toolName == 'verticalSearch';
    _latestSearchMode = searchMode;
    _latestSearchProvider = searchProvider;
    _latestToolUsed = toolUsed;
    petController.setModeAndMessage(petMode, message);
    if (saveToHistory) {
      final timestamp = DateTime.now();
      final turnId = '${_activeSessionId}_${timestamp.microsecondsSinceEpoch}';
      _history.add(
        ConversationTurn(
          timestamp: timestamp,
          userText: userText,
          petReply: message,
          toolName: toolName,
          sessionId: _activeSessionId,
          emotionTag: emotionTag,
          petMood: petController.mood,
          toolUsed: toolUsed,
          searchMode: searchMode,
          searchProvider: searchProvider,
          sources: sources,
          memoryUsed: memoryUsed,
          usedMemoryIds: usedMemoryIds,
          memoryContextSummary: memoryContextSummary,
          memoryProvider: memoryProvider,
        ),
      );
      await _persistHistory();
      _extractMemoryInBackground(
        turnId: turnId,
        userText: userText,
        aiReply: message,
        emotion: emotionTag,
      );
    }
    notifyListeners();
    await ttsService.speak(
      message,
      enabled: profileController.ttsEnabled,
      volume: profileController.petVolume,
      speechStyle: profileController.speechStyle,
      onStart: () async {
        petController.setMode(PetMode.talking, isSpeaking: true);
      },
      onComplete: () async {
        petController.setMode(petMode, isSpeaking: false);
      },
      onError: () async {
        petController.setMode(petMode, isSpeaking: false);
      },
    );
  }

  static String _newSessionId() =>
      DateTime.now().microsecondsSinceEpoch.toString();

  Future<void> _persistHistory() async {
    await storageService.saveConversationHistory(_history);
  }

  Future<_MemoryContextResult> _loadMemoryContext(String userText) async {
    try {
      final result =
          await memoryController.buildMemoryContext(userText: userText);
      if (result == null || result['memoryUsed'] != true) {
        return const _MemoryContextResult();
      }
      final rawIds = result['usedMemoryIds'] as List<dynamic>? ?? const [];
      return _MemoryContextResult(
        memoryUsed: true,
        usedMemoryIds: rawIds,
        memoryContextSummary: result['memoryContextSummary']?.toString(),
        memoryProvider: result['provider']?.toString(),
      );
    } catch (_) {
      return const _MemoryContextResult();
    }
  }

  void _extractMemoryInBackground({
    required String turnId,
    required String userText,
    required String aiReply,
    required String emotion,
  }) {
    final normalized = userText.trim();
    if (normalized.length < 4) return;
    unawaited(
      memoryController.extractMemory(
        sessionId: _activeSessionId,
        turnId: turnId,
        userText: normalized,
        aiReply: aiReply,
        emotion: emotion,
      ),
    );
  }

  void _applyPetEmotionState(String emotion, PetMode mode) {
    final state = switch (emotion) {
      'happy' => (mood: 'happy', expression: 'smile', action: 'celebrate'),
      'sad' => (mood: 'caring', expression: 'concerned', action: 'comfort'),
      'lonely' => (mood: 'caring', expression: 'concerned', action: 'comfort'),
      'anxious' => (
          mood: 'worried',
          expression: 'concerned',
          action: 'comfort'
        ),
      'tired' => (mood: 'sleepy', expression: 'sleepy', action: 'rest'),
      'angry' => (mood: 'caring', expression: 'concerned', action: 'comfort'),
      _ => (mood: 'neutral', expression: 'normal', action: 'idle'),
    };
    petController.updateEmotionState(
      mood: state.mood,
      expression: state.expression,
      action: state.action,
      mode: mode,
    );
  }
}

class _MemoryContextResult {
  const _MemoryContextResult({
    this.memoryUsed = false,
    this.usedMemoryIds = const [],
    this.memoryContextSummary,
    this.memoryProvider,
  });

  final bool memoryUsed;
  final List<dynamic> usedMemoryIds;
  final String? memoryContextSummary;
  final String? memoryProvider;
}
