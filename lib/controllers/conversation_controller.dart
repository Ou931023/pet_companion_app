import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/conversation_session_summary.dart';
import '../models/conversation_turn.dart';
import '../models/companion_reply.dart';
import '../models/emotion_result.dart';
import '../models/language_route.dart';
import '../models/pet_status.dart';
import '../models/realtime_timeout.dart';
import '../models/source_reference.dart';
import '../services/ai_navigation_service.dart';
import '../services/ai_tool_router.dart';
import '../services/companion_reply_strategy_service.dart';
import '../services/emotion_services.dart';
import '../services/local_storage_service.dart';
import '../services/language_routing_service.dart';
import '../services/mock_speech_to_text_service.dart';
import '../services/openai_speech_to_text_service.dart';
import '../services/search_service.dart';
import '../services/speech_to_text_service.dart';
import '../services/taigi_asr_service.dart';
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
    required this.companionReplyStrategy,
    required this.languageRoutingService,
    required this.taigiAsrService,
    this.timeoutConfig = const RealtimeTimeoutConfig(),
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
  final CompanionReplyStrategyService companionReplyStrategy;
  final LanguageRoutingService languageRoutingService;
  final TaigiAsrService taigiAsrService;
  final RealtimeTimeoutConfig timeoutConfig;

  final List<ConversationTurn> _history = [];
  String _activeSessionId = _newSessionId();
  bool _isRecording = false;
  bool _isBusy = false;
  bool _isAwaitingPetReply = false;
  String _latestUserText = '';
  String _latestReply = '';
  String _currentPartialTranscript = '';
  String _currentFinalTranscript = '';
  String _currentDraftText = '';
  bool _isUserSpeaking = false;
  bool _isAwaitingFinalTranscript = false;
  bool _isTaigiAsrRecording = false;
  bool _isTaigiAsrProcessing = false;
  bool _isCheckingTaigiAsrStatus = false;
  String _taigiAsrStatusMessage = '';
  String _pendingTaigiAsrTranscript = '';
  List<SourceReference> _latestSources = const [];
  bool _latestReplyIsSearch = false;
  String _latestSearchMode = '';
  String _latestSearchProvider = '';
  String _latestToolUsed = '';
  CompanionReplyDebugInfo? _latestCompanionDebugInfo;
  Timer? _ttsTimeoutTimer;

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
  bool get isAwaitingPetReply => _isAwaitingPetReply;
  String get activeSessionId => _activeSessionId;
  String get latestUserText => _latestUserText;
  String get latestReply => _latestReply;
  String get currentPartialTranscript => _currentPartialTranscript;
  String get currentFinalTranscript => _currentFinalTranscript;
  String get currentDraftText => _currentDraftText;
  bool get isUserSpeaking => _isUserSpeaking;
  bool get isAwaitingFinalTranscript => _isAwaitingFinalTranscript;
  bool get isTaigiAsrRecording => _isTaigiAsrRecording;
  bool get isTaigiAsrProcessing => _isTaigiAsrProcessing;
  bool get isCheckingTaigiAsrStatus => _isCheckingTaigiAsrStatus;
  String get taigiAsrStatusMessage => _taigiAsrStatusMessage;
  String get pendingTaigiAsrTranscript => _pendingTaigiAsrTranscript;
  bool get hasPendingTaigiAsrTranscript =>
      _pendingTaigiAsrTranscript.trim().isNotEmpty;
  bool get hasTemporaryUserBubble =>
      temporaryUserBubbleText.trim().isNotEmpty ||
      temporaryUserBubbleStatus.isNotEmpty;
  String get temporaryUserBubbleText {
    if (_isUserSpeaking || _isAwaitingFinalTranscript) {
      final partial = _currentPartialTranscript.trim();
      return partial.isEmpty ? '正在聽你說話…' : partial;
    }
    return _currentDraftText.trim();
  }

  String get temporaryUserBubbleStatus {
    if (_isUserSpeaking) return '聆聽中';
    if (_isAwaitingFinalTranscript) return '辨識中';
    if (_currentDraftText.trim().isNotEmpty) return '輸入中';
    return '';
  }

  List<SourceReference> get latestSources => List.unmodifiable(_latestSources);
  bool get latestReplyIsSearch => _latestReplyIsSearch;
  String get latestSearchMode => _latestSearchMode;
  String get latestSearchProvider => _latestSearchProvider;
  String get latestToolUsed => _latestToolUsed;
  CompanionReplyDebugInfo? get latestCompanionDebugInfo =>
      _latestCompanionDebugInfo;
  String get latestLanguageHint {
    final userTurn = _latestUserTurnWithLanguage();
    return userTurn.languageHint;
  }

  String get latestLanguageContextLabel {
    final routeReason = _latestUserTurnWithLanguage().routeReason;
    final hint = latestLanguageHint;
    if (hint == TranscriptLanguageHint.taigi.value) {
      return routeReason == 'taigi_mixed_zh_detected' ? '台語混中文' : '台語語境';
    }
    if (hint == TranscriptLanguageHint.mixed.value) return '台語混中文';
    if (hint == TranscriptLanguageHint.zh.value) return '中文語境';
    return '';
  }

  Future<void> loadHistory() async {
    final turns = await storageService.loadConversationHistory();
    _history
      ..clear()
      ..addAll(turns);
    // CR-0009：換帳號時一併清掉上一個帳號殘留的「最新回覆」顯示狀態。
    // （問候 / 部分回覆用 saveToHistory:false，不進 _history 卻會設 _latestReply，
    //  loadHistory 若只清 _history，主對話泡泡會還顯示前一帳號的寵物名/內容。）
    _resetLatestReplyState();
    notifyListeners();
  }

  /// 清掉「最新回覆」相關的顯示暫存（換帳號 / 重置時用）。
  void _resetLatestReplyState() {
    _latestReply = '';
    _latestUserText = '';
    _isAwaitingPetReply = false;
    _latestSources = const [];
    _latestReplyIsSearch = false;
    _latestSearchMode = '';
    _latestSearchProvider = '';
    _latestToolUsed = '';
    _latestCompanionDebugInfo = null;
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

  Future<void> handleTaigiAsrTranscript(String text) async {
    final normalized = text.trim();
    if (normalized.isEmpty) return;
    await _handleUserText(
      normalized,
      languageRoute: LanguageRouteResult(
        strategyName: 'taigiShortRecording',
        languageHint: TranscriptLanguageHint.taigi,
        routeReason: 'taigi_asr_transcript',
        isFallback: false,
        transcript: normalized,
        replyLanguage: ReplyLanguage.mixedZhTaigi,
      ),
      asrSource: 'taigi-asr',
    );
  }

  Future<void> refreshTaigiAsrStatus() async {
    if (_isCheckingTaigiAsrStatus ||
        _isTaigiAsrRecording ||
        _isTaigiAsrProcessing) {
      return;
    }
    _isCheckingTaigiAsrStatus = true;
    _taigiAsrStatusMessage = '台語語音辨識準備中';
    notifyListeners();
    try {
      final status = await taigiAsrService.fetchStatus(
        sttProxyUrl: profileController.sttProxyUrl,
      );
      _taigiAsrStatusMessage = status.userMessage;
    } finally {
      _isCheckingTaigiAsrStatus = false;
      notifyListeners();
    }
  }

  Future<bool> startTaigiShortRecording({bool realtimeBusy = false}) async {
    if (_isBusy ||
        realtimeBusy ||
        _isTaigiAsrRecording ||
        _isTaigiAsrProcessing) {
      if (realtimeBusy) {
        _taigiAsrStatusMessage = '請先結束目前語音對話。';
        notifyListeners();
      }
      return false;
    }
    _pendingTaigiAsrTranscript = '';
    _taigiAsrStatusMessage = '台語語音辨識準備中';
    notifyListeners();
    final status = await taigiAsrService.fetchStatus(
      sttProxyUrl: profileController.sttProxyUrl,
    );
    if (!status.available) {
      _taigiAsrStatusMessage = status.userMessage;
      notifyListeners();
      return false;
    }
    _taigiAsrStatusMessage = '';
    try {
      await taigiAsrService.startRecording();
      _isTaigiAsrRecording = true;
      _taigiAsrStatusMessage = '台語錄音中';
      notifyListeners();
      return true;
    } catch (_) {
      _taigiAsrStatusMessage = '請先開啟麥克風權限，再試一次。';
      notifyListeners();
      return false;
    }
  }

  Future<void> stopTaigiShortRecordingAndTranscribe() async {
    if (!_isTaigiAsrRecording || _isTaigiAsrProcessing) return;
    _isTaigiAsrRecording = false;
    _isTaigiAsrProcessing = true;
    _taigiAsrStatusMessage = '台語辨識中，請稍等';
    notifyListeners();
    File? audioFile;
    try {
      audioFile = await taigiAsrService.stopRecording();
      if (audioFile == null) {
        _taigiAsrStatusMessage = '我這次沒有聽清楚，可以再說一次嗎？';
        return;
      }
      final result = await taigiAsrService.transcribeAudio(
        audioFile: audioFile,
        sttProxyUrl: profileController.sttProxyUrl,
      );
      if (!result.success) {
        _taigiAsrStatusMessage = result.message;
        return;
      }
      final transcript = result.transcript.trim();
      if (transcript.isEmpty) {
        _taigiAsrStatusMessage = '我這次沒有聽清楚，可以再說一次嗎？';
        return;
      }
      _pendingTaigiAsrTranscript = transcript;
      _taigiAsrStatusMessage = '請確認辨識內容';
    } finally {
      _isTaigiAsrProcessing = false;
      if (audioFile != null) {
        unawaited(audioFile.delete().catchError((_) => audioFile!));
      }
      notifyListeners();
    }
  }

  Future<void> confirmPendingTaigiAsrTranscript() async {
    final transcript = _pendingTaigiAsrTranscript.trim();
    if (transcript.isEmpty || _isBusy || _isTaigiAsrProcessing) return;
    _pendingTaigiAsrTranscript = '';
    _taigiAsrStatusMessage = '';
    notifyListeners();
    await handleTaigiAsrTranscript(transcript);
  }

  void clearPendingTaigiAsrTranscript() {
    if (_pendingTaigiAsrTranscript.isEmpty &&
        _taigiAsrStatusMessage.isEmpty) {
      return;
    }
    _pendingTaigiAsrTranscript = '';
    _taigiAsrStatusMessage = '';
    _isCheckingTaigiAsrStatus = false;
    notifyListeners();
  }

  void updateDraftText(String text) {
    final normalized = text.trim();
    if (_currentDraftText == normalized) return;
    _currentDraftText = normalized;
    notifyListeners();
  }

  void clearDraftText() {
    if (_currentDraftText.isEmpty) return;
    _currentDraftText = '';
    notifyListeners();
  }

  void beginRealtimeUserSpeech() {
    _isUserSpeaking = true;
    _isAwaitingFinalTranscript = true;
    _currentPartialTranscript = '';
    _currentDraftText = '';
    _latestUserText = '';
    _latestReply = '';
    _isAwaitingPetReply = false;
    notifyListeners();
  }

  void markAwaitingFinalTranscript() {
    _isUserSpeaking = false;
    _isAwaitingFinalTranscript = true;
    notifyListeners();
  }

  void updateRealtimePartialTranscript(String text) {
    final normalized = text.trim();
    _isUserSpeaking = true;
    _isAwaitingFinalTranscript = true;
    if (_currentPartialTranscript == normalized) {
      notifyListeners();
      return;
    }
    _currentPartialTranscript = normalized;
    notifyListeners();
  }

  void commitRealtimeFinalTranscript(
    String text, {
    bool awaitingPetReply = true,
  }) {
    final normalized = text.trim();
    clearRealtimeTranscriptState(notify: false);
    if (normalized.isEmpty) {
      notifyListeners();
      return;
    }
    _currentFinalTranscript = normalized;
    showUserBubbleMessage(
      normalized,
      awaitingPetReply: awaitingPetReply,
      clearPetReply: true,
    );
  }

  void clearRealtimeTranscriptState({bool notify = true}) {
    _currentPartialTranscript = '';
    _isUserSpeaking = false;
    _isAwaitingFinalTranscript = false;
    if (notify) {
      notifyListeners();
    }
  }

  void showUserBubbleMessage(
    String text, {
    bool awaitingPetReply = false,
    bool clearPetReply = true,
  }) {
    final normalized = text.trim();
    if (normalized.isEmpty) return;
    clearRealtimeTranscriptState(notify: false);
    _currentDraftText = '';
    _latestUserText = normalized;
    if (clearPetReply) {
      _latestReply = '';
      _latestSources = const [];
      _latestReplyIsSearch = false;
      _latestSearchMode = '';
      _latestSearchProvider = '';
      _latestToolUsed = '';
    }
    _isAwaitingPetReply = awaitingPetReply;
    notifyListeners();
  }

  void showPetBubbleMessage(String message) {
    final normalized = message.trim();
    if (normalized.isEmpty) return;
    _latestReply = normalized;
    _isAwaitingPetReply = false;
    _latestSources = const [];
    _latestReplyIsSearch = false;
    _latestSearchMode = '';
    _latestSearchProvider = '';
    _latestToolUsed = '';
    notifyListeners();
  }

  bool shouldHandleAsLocalCommand(String text) {
    return reminderController.isCreateReminderCommand(text) ||
        reminderController.isListReminderCommand(text) ||
        toolRouter.shouldHandleLocally(text);
  }

  void appendExternalTurn(ConversationTurn turn) {
    if (turn.userText.trim().isNotEmpty) {
      _latestUserText = turn.userText.trim();
    }
    if (turn.petReply.trim().isEmpty && turn.userText.trim().isNotEmpty) {
      _latestReply = '';
      _isAwaitingPetReply = true;
    } else if (turn.petReply.trim().isNotEmpty) {
      _latestReply = turn.petReply.trim();
      _isAwaitingPetReply = false;
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
        turnId: turn.turnId,
        sessionId: turn.sessionId.isEmpty ? _activeSessionId : turn.sessionId,
        emotionTag: turn.emotionTag,
        petMood: turn.petMood,
        toolUsed: turn.toolUsed,
        searchMode: turn.searchMode,
        searchProvider: turn.searchProvider,
        sources: turn.sources,
        asrSource: turn.asrSource,
        languageHint: turn.languageHint,
        routeReason: turn.routeReason,
        replyLanguage: turn.replyLanguage,
      ),
    );
    unawaited(_persistHistory());
    notifyListeners();
  }

  Future<void> handleRealtimeAssistantReply(
    String message, {
    String turnId = '',
  }) async {
    _latestReply = message;
    _isAwaitingPetReply = false;
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
        turnId: turnId,
        sessionId: _activeSessionId,
        petMood: petController.mood,
        replyLanguage: _replyLanguageForText(_latestUserText).value,
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

  Future<void> _handleUserText(
    String text, {
    LanguageRouteResult? languageRoute,
    String asrSource = 'text_input',
  }) async {
    if (_isBusy) return;
    _isBusy = true;
    final resolvedLanguageRoute = languageRoute ??
        languageRoutingService.previewRouteFromText(
          mode: profileController.voiceLanguageMode,
          text: text,
          manualStrategyName: profileController.manualAsrStrategy,
        );
    clearDraftText();
    showUserBubbleMessage(text, awaitingPetReply: true);
    try {
      final navigationIntent = navigationService.detect(text);
      if (navigationIntent != null) {
        navigationController.navigateTo(navigationIntent.route);
        final reply = _buildCompanionReply(
          userText: text,
          emotion: emotionFusionService.analyze(text: text),
          suggestedAction: 'route',
          optionalSuggestion: navigationIntent.reply,
          routeInfo: navigationIntent.route,
          languageRoute: resolvedLanguageRoute,
        );
        await _deliverPetReply(
          reply,
          petMode: PetMode.listening,
          toolName: 'navigation',
          userText: text,
          languageRoute: resolvedLanguageRoute,
          asrSource: asrSource,
        );
        return;
      }
      final emotion = emotionFusionService.analyze(text: text);
      final emotionMode = petEmotionMapper.modeFor(emotion.emotion);
      _applyPetEmotionState(emotion.emotion, emotionMode);
      unawaited(petStatsController.applyConversationEmotion(emotion.emotion));

      if (reminderController.isCreateReminderCommand(text)) {
        final reminder = await reminderController.createFromVoice(text);
        final rawReply = reminder == null
            ? '我還沒聽清楚提醒時間，可以說「提醒我晚上八點吃藥」。'
            : '好，我會在${reminder.repeatLabel}${reminder.timeLabel}提醒你${reminder.title}。';
        await _deliverPetReply(
          _buildCompanionReply(
            userText: text,
            emotion: emotion,
            suggestedAction: 'reminder',
            optionalSuggestion: rawReply,
            languageRoute: resolvedLanguageRoute,
          ),
          petMode: emotionMode,
          toolName: 'createReminder',
          userText: text,
          emotionTag: emotion.emotion,
          languageRoute: resolvedLanguageRoute,
          asrSource: asrSource,
        );
        return;
      }
      if (reminderController.isListReminderCommand(text)) {
        await _deliverPetReply(
          _buildCompanionReply(
            userText: text,
            emotion: emotion,
            suggestedAction: 'reminder',
            optionalSuggestion: reminderController.listSummary(),
            languageRoute: resolvedLanguageRoute,
          ),
          petMode: emotionMode,
          toolName: 'listReminders',
          userText: text,
          emotionTag: emotion.emotion,
          languageRoute: resolvedLanguageRoute,
          asrSource: asrSource,
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
          _buildCompanionReply(
            userText: text,
            emotion: emotion,
            suggestedAction: _searchActionLabel(text),
            optionalSuggestion: reply,
            memoryHints: [
              if (memoryContext.memoryContextSummary?.trim().isNotEmpty == true)
                memoryContext.memoryContextSummary!.trim(),
            ],
            languageRoute: resolvedLanguageRoute,
          ),
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
          languageRoute: resolvedLanguageRoute,
          asrSource: asrSource,
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
      await _deliverPetReply(
        _buildCompanionReply(
          userText: text,
          emotion: emotion,
          suggestedAction: _toolActionLabel(toolResult.toolName),
          optionalSuggestion: toolResult.message,
          memoryHints: [
            if (memoryContext.memoryContextSummary?.trim().isNotEmpty == true)
              memoryContext.memoryContextSummary!.trim(),
          ],
          languageRoute: resolvedLanguageRoute,
        ),
        petMode: petMode,
        toolName: toolResult.toolName,
        userText: text,
        emotionTag: emotion.emotion,
        memoryUsed: memoryContext.memoryUsed,
        usedMemoryIds: memoryContext.usedMemoryIds,
        memoryContextSummary: memoryContext.memoryContextSummary,
        memoryProvider: memoryContext.memoryProvider,
        languageRoute: resolvedLanguageRoute,
        asrSource: asrSource,
      );
    } catch (_) {
      await _deliverPetReply(
        '我剛剛有點卡住了，不過我還在這裡陪你，我們可以再說一次。',
        petMode: PetMode.caring,
        toolName: 'chatFallback',
        userText: text,
        languageRoute: resolvedLanguageRoute,
        asrSource: asrSource,
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
    LanguageRouteResult? languageRoute,
    String asrSource = '',
  }) async {
    _latestReply = message;
    _isAwaitingPetReply = false;
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
          turnId: turnId,
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
          asrSource: userText.trim().isEmpty ? '' : asrSource,
          languageHint: languageRoute?.languageHint.value ?? '',
          routeReason: languageRoute?.routeReason ?? '',
          replyLanguage: languageRoute?.replyLanguage.value ??
              _replyLanguageForText(userText).value,
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
    final ttsTimeout = _estimatedTtsTimeout(message);
    var ttsTimedOut = false;
    if (profileController.ttsEnabled) {
      _startTtsTimeout(ttsTimeout, () async {
        ttsTimedOut = true;
        await ttsService.stop();
        petController.setMode(PetMode.listening, isSpeaking: false);
        notifyListeners();
      });
    }
    await ttsService.speak(
      message,
      enabled: profileController.ttsEnabled,
      volume: profileController.petVolume,
      speechStyle: profileController.speechStyle,
      onStart: () async {
        _startTtsTimeout(ttsTimeout, () async {
          ttsTimedOut = true;
          await ttsService.stop();
          petController.setMode(PetMode.listening, isSpeaking: false);
          notifyListeners();
        });
        petController.setMode(PetMode.talking, isSpeaking: true);
      },
      onComplete: () async {
        _cancelTtsTimeout();
        if (ttsTimedOut) return;
        petController.setMode(petMode, isSpeaking: false);
      },
      onError: () async {
        _cancelTtsTimeout();
        if (ttsTimedOut) return;
        petController.setMode(petMode, isSpeaking: false);
      },
    );
  }

  String _buildCompanionReply({
    required String userText,
    required EmotionResult emotion,
    required String suggestedAction,
    required String optionalSuggestion,
    String routeInfo = '',
    List<String> memoryHints = const [],
    LanguageRouteResult? languageRoute,
  }) {
    final context = CompanionContext(
      userText: userText,
      detectedEmotion: emotion.emotion,
      fusedEmotion: emotion.emotion,
      memoryHints: memoryHints,
      routeInfo: routeInfo,
      userStateHints: _userStateHintsFor(userText),
      suggestedAction: suggestedAction,
      optionalSuggestion: optionalSuggestion,
      petName: profileController.petName,
      conversationHistory: history.take(6).toList(),
      replyLanguage:
          languageRoute?.replyLanguage ?? _replyLanguageForText(userText),
    );
    final plan = companionReplyStrategy.buildPlan(context);
    _latestCompanionDebugInfo = companionReplyStrategy.debugInfo(context);
    return companionReplyStrategy.compose(plan);
  }

  String _toolActionLabel(String toolName) {
    return switch (toolName) {
      'companionContent' => 'story',
      'webSearch' => 'search',
      'dailyCheckIn' ||
      'buyShopItem' ||
      'changeSettings' ||
      'completeCareTask' ||
      'getUserStatus' ||
      'getDailyTasks' =>
        'task',
      _ => '',
    };
  }

  String _searchActionLabel(String text) {
    if (text.contains('新聞')) return 'news';
    return 'search';
  }

  UserStateHints _userStateHintsFor(String userText) {
    final recent = history.take(3).map((turn) => turn.userText).join(' ');
    final combined = '$recent $userText';
    return UserStateHints(
      mentionedLonely:
          _containsAny(combined, ['孤單', '沒有人陪', '沒人陪', '家裡好安靜', '足安靜', '厝內']),
      mentionedTired: _containsAny(combined, ['累', '疲倦', '沒精神', '想睡', '足累']),
      mentionedPoorSleep:
          _containsAny(combined, ['睡不好', '睡不著', '失眠', '睡不太著', '袂好睏', '睏袂好']),
      mentionedLowAppetite: _containsAny(combined, ['不太想吃飯', '沒胃口', '吃不下']),
      mentionedPainOrDiscomfort:
          _containsAny(combined, ['不舒服', '痛', '疼', '頭暈']),
      lastConcernAt: DateTime.now(),
    );
  }

  bool _containsAny(String text, List<String> terms) {
    return terms.any(text.contains);
  }

  ReplyLanguage _replyLanguageForText(String userText) {
    return LanguageRoutingService.replyLanguageForTranscript(
      userText,
      profileController.voiceLanguageMode,
      profileController.manualAsrStrategy,
    );
  }

  ConversationTurn _latestUserTurnWithLanguage() {
    for (final turn in _history.reversed) {
      if (turn.userText.trim().isNotEmpty) return turn;
    }
    return ConversationTurn(
      timestamp: DateTime.fromMillisecondsSinceEpoch(0),
      userText: '',
      petReply: '',
      toolName: '',
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

  Duration _estimatedTtsTimeout(String message) {
    final estimated = Duration(
      milliseconds: 2500 + (message.runes.length * 260),
    );
    final minimum = timeoutConfig.ttsTimeout;
    return estimated > minimum ? estimated : minimum;
  }

  void _startTtsTimeout(
    Duration duration,
    Future<void> Function() onTimeout,
  ) {
    _cancelTtsTimeout();
    _ttsTimeoutTimer = Timer(duration, () {
      debugPrint(
        '[TTS_TIMEOUT] fired duration=${duration.inSeconds}s',
      );
      unawaited(onTimeout());
    });
  }

  void _cancelTtsTimeout() {
    _ttsTimeoutTimer?.cancel();
    _ttsTimeoutTimer = null;
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

  @override
  void dispose() {
    _cancelTtsTimeout();
    super.dispose();
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
