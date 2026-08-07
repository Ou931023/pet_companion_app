import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/conversation_session_summary.dart';
import '../models/conversation_turn.dart';
import '../models/companion_reply.dart';
import '../models/emotion_result.dart';
import '../models/language_route.dart';
import '../models/pet_status.dart';
import '../models/realtime_timeout.dart';
import '../models/source_reference.dart';
import '../onboarding/coach_mark_controller.dart';
import '../services/ai_navigation_service.dart';
import '../services/ai_tool_router.dart';
import '../services/companion_reply_strategy_service.dart';
import '../services/conversation_title_service.dart';
import '../services/emotion_services.dart';
import '../services/local_storage_service.dart';
import '../services/language_routing_service.dart';
import '../services/mock_speech_to_text_service.dart';
import '../services/search_service.dart';
import '../services/speech_to_text_service.dart';
import '../services/taigi_asr_service.dart';
import '../services/text_to_speech_service.dart';
import '../utils/app_log.dart';
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
    required this.sttService,
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
    this.coachMarkController,
    this.timeoutConfig = const RealtimeTimeoutConfig(),
    this.titleService = const ConversationTitleService(),
  });

  final ProfileController profileController;
  final PetController petController;
  final AiToolRouter toolRouter;
  final TextToSpeechService ttsService;

  /// 語音辨識服務（介面注入）。正式版注入 [OpenAiSpeechToTextService]（金鑰留在
  /// 後端代理，Flutter 不持有 key）；dev / test 可注入 [MockSpeechToTextService]。
  final SpeechToTextService sttService;
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
  final CoachMarkController? coachMarkController;
  final RealtimeTimeoutConfig timeoutConfig;
  final ConversationTitleService titleService;

  final List<ConversationTurn> _history = [];
  // CR-0027：LLM 產生的對話標題快取（sessionId → title），持久化、各帳號獨立。
  final Map<String, String> _sessionTitles = {};
  final Set<String> _titleInFlight = {};
  String _activeSessionId = _newSessionId();
  bool _isRecording = false;
  bool _isBusy = false;
  bool _isAwaitingPetReply = false;
  String _latestUserText = '';
  String _latestReply = '';
  String _currentPartialTranscript = '';
  String _currentFinalTranscript = '';
  String _currentDraftText = '';
  // Realtime 寵物（assistant）語音回覆的「即時」逐字文字：在寵物說話過程中由
  // assistantPartialText 持續更新，讓字幕跟著聲音走；寵物這句講完（最終 assistantText）
  // 或新的一輪開始時清空，改由最終靜態文字接手。純顯示用，不寫入對話紀錄。
  String _liveRealtimeReply = '';
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
      // 標題優先序（CR-0027）：① LLM 快取標題 → ② 本地 fallback（第一則使用者
      // 訊息 → 第一則訊息 → 「未命名對話」）。
      final cached = _sessionTitles[entry.key]?.trim() ?? '';
      final title = cached.isNotEmpty ? cached : _fallbackTitle(turns);
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
        title: title,
        updatedAt: updatedAt,
        lastPreview: lastPreview.isEmpty ? '語音對話' : lastPreview,
        emotionTag: emotion,
      );
    }).toList();
    summaries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return summaries;
  }

  /// 還沒有 LLM 標題時的本地 fallback：第一則使用者訊息 → 第一則任何訊息 →
  /// 「未命名對話」，整理成 ≤14 字短句（去換行、去頭尾空白；不含情緒 metadata）。
  String _fallbackTitle(List<ConversationTurn> turns) {
    var firstUser = '';
    var firstAny = '';
    for (final t in turns) {
      final u = t.userText.trim();
      final p = t.petReply.trim();
      if (firstAny.isEmpty) firstAny = u.isNotEmpty ? u : p;
      if (u.isNotEmpty) {
        firstUser = u;
        break;
      }
    }
    final base = firstUser.isNotEmpty ? firstUser : firstAny;
    final shortened = _shortenTitle(base);
    return shortened.isEmpty ? '未命名對話' : shortened;
  }

  String _shortenTitle(String text) {
    final cleaned = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) return '';
    final runes = cleaned.runes.toList();
    if (runes.length <= 14) return cleaned;
    return String.fromCharCodes(runes.take(14));
  }

  /// 開「對話紀錄」頁時呼叫：為還沒有 LLM 標題、且有內容的 session 產生標題，
  /// 結果快取＋持久化，並 notify 讓卡片即時從 fallback 更新成 LLM 標題。
  /// 失敗安靜略過（卡片續用 fallback）。
  Future<void> ensureSessionTitles() async {
    final map = <String, List<ConversationTurn>>{};
    for (final turn in _history) {
      final id = turn.sessionId.isEmpty ? 'legacy' : turn.sessionId;
      map.putIfAbsent(id, () => []).add(turn);
    }
    for (final entry in map.entries) {
      final id = entry.key;
      if ((_sessionTitles[id]?.trim().isNotEmpty ?? false)) continue;
      if (_titleInFlight.contains(id)) continue;
      final firstUserText = entry.value
          .firstWhere(
            (t) => t.userText.trim().isNotEmpty,
            orElse: () => entry.value.first,
          )
          .userText
          .trim();
      final conversationText = entry.value
          .map((t) {
            final u = t.userText.trim();
            final p = t.petReply.trim();
            return [if (u.isNotEmpty) '我：$u', if (p.isNotEmpty) '寵物：$p']
                .join('\n');
          })
          .where((line) => line.isNotEmpty)
          .take(6)
          .join('\n');
      if (firstUserText.isEmpty && conversationText.isEmpty) continue;
      _titleInFlight.add(id);
      final title = await titleService.generateTitle(
        firstUserText: firstUserText,
        conversationText: conversationText,
      );
      _titleInFlight.remove(id);
      if (title != null && title.trim().isNotEmpty) {
        _sessionTitles[id] = title.trim();
        await storageService.saveConversationTitles(_sessionTitles);
        notifyListeners();
      }
    }
  }

  /// 刪除「對話紀錄列表」中的一整則紀錄（某個 session 的所有 turn）+ 其標題快取。
  /// 只動本機對話歷史，**不影響長期記憶、Care Alert、DailyCareTask**。
  /// 找不到該則 → 回 false。
  Future<bool> deleteConversationSession(String sessionId) async {
    final before = _history.length;
    _history.removeWhere(
      (t) => (t.sessionId.isEmpty ? 'legacy' : t.sessionId) == sessionId,
    );
    final removed = _history.length != before;
    final hadTitle = _sessionTitles.remove(sessionId) != null;
    if (!removed && !hadTitle) return false;
    await _persistHistory();
    if (hadTitle) {
      await storageService.saveConversationTitles(_sessionTitles);
    }
    notifyListeners();
    return removed;
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

  /// CR-0072：取當前 session 最近 [maxTurns] 輪對話，轉成 companion chat 的
  /// 短期歷史（user/assistant 交錯、oldest→newest，空字串那側略過）。
  /// 在記錄當前這一輪「之前」呼叫，故不含當前句。後端 sanitizeHistory 會再做
  /// role/長度/則數清洗，這裡只負責提供來源。
  List<Map<String, String>> _recentChatHistory({int maxTurns = 6}) {
    final turns = turnsForSession(_activeSessionId);
    final recent =
        turns.length > maxTurns ? turns.sublist(turns.length - maxTurns) : turns;
    final history = <Map<String, String>>[];
    for (final turn in recent) {
      final userText = turn.userText.trim();
      final petReply = turn.petReply.trim();
      if (userText.isNotEmpty) {
        history.add({'role': 'user', 'content': userText});
      }
      if (petReply.isNotEmpty) {
        history.add({'role': 'assistant', 'content': petReply});
      }
    }
    return history;
  }

  /// 刪除「對話紀錄」中的單筆紀錄（聊天歷史裡的一筆 user／pet 交換）。
  ///
  /// 只移除本機對話歷史並重新保存；**完全不會動到 MemoryService 的長期記憶**——
  /// 長期記憶是另一套抽取後保存的重要資訊，由 MemoryController / MemoryService
  /// 管理，本方法不碰。傳入的 [turn] 應取自 [turnsForSession] / [history]
  /// （即 _history 中的同一個物件，採身分比對移除）。
  ///
  /// 回傳是否真的有刪到該筆（找不到 → false，UI 可顯示白話訊息）。
  Future<bool> deleteConversationTurn(ConversationTurn turn) async {
    final before = _history.length;
    _history.remove(turn);
    if (_history.length == before) return false;
    await _persistHistory();
    notifyListeners();
    return true;
  }

  /// 刪除某一筆紀錄中的「單一則」訊息：[deleteUser] 為 true 只刪使用者那句，
  /// false 只刪寵物那句。若刪掉後該筆兩側都空了 → 整筆移除。
  ///
  /// 與 [deleteConversationTurn] 一樣只動本機對話歷史，**不影響長期記憶**。
  /// 找不到該筆 → 回傳 false。
  Future<bool> deleteConversationMessage(
    ConversationTurn turn, {
    required bool deleteUser,
  }) async {
    final index = _history.indexOf(turn);
    if (index < 0) return false;
    final updated =
        deleteUser ? turn.copyWith(userText: '') : turn.copyWith(petReply: '');
    if (updated.userText.trim().isEmpty && updated.petReply.trim().isEmpty) {
      _history.removeAt(index);
    } else {
      _history[index] = updated;
    }
    await _persistHistory();
    notifyListeners();
    return true;
  }

  bool get isBusy => _isBusy;
  bool get isAwaitingPetReply => _isAwaitingPetReply;
  String get activeSessionId => _activeSessionId;
  String get latestUserText => _latestUserText;
  String get latestReply => _latestReply;
  String get currentPartialTranscript => _currentPartialTranscript;
  String get currentFinalTranscript => _currentFinalTranscript;
  String get currentDraftText => _currentDraftText;
  String get liveRealtimeReply => _liveRealtimeReply;
  bool get isRealtimeStreaming => _liveRealtimeReply.trim().isNotEmpty;
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
    final titles = await storageService.loadConversationTitles();
    _sessionTitles
      ..clear()
      ..addAll(titles);
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

  /// 目前使用的語音辨識服務。型別統一為 [SpeechToTextService] 介面，正式版直接
  /// 使用注入的正式服務（[OpenAiSpeechToTextService]），不在前端持有任何金鑰。
  SpeechToTextService _currentSttService() => sttService;

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
    final stt = _currentSttService();
    // dev / test 的本機 mock 辨識路徑：僅當實際注入的是 mock 服務時才走。
    // 正式版注入 OpenAiSpeechToTextService，不會進這裡，也不會用假 transcript。
    if (profileController.sttMode == SttMode.mock &&
        stt is MockSpeechToTextService) {
      stt.setNextTranscript(mockText ?? '幫我簽到');
      await _processSttResult(await stt.transcribeAudio(File('mock.wav')));
      return;
    }
    try {
      final audioFile = await stt.stopRecording();
      if (audioFile == null) {
        await _deliverPetReply(
          '我剛剛沒有聽到聲音，可以再說一次嗎？',
          petMode: PetMode.listening,
          toolName: 'sttEmpty',
        );
        return;
      }
      final result = await stt.retryTranscription(audioFile);
      await _processSttResult(result);
    } catch (_) {
      // 正式版：辨識出狀況不切回 mock、不假裝成功，用長者聽得懂的話請他再說一次。
      // dev / test（mockServicesEnabled）才保留切回本機 mock 的離線備援。
      if (AppConfig.mockServicesEnabled) {
        await profileController.setSttMode(SttMode.mock);
        await _deliverPetReply(
          '連線剛剛不太穩，我先用手機裡的辨識，麻煩你再說一次。',
          petMode: PetMode.listening,
          toolName: 'sttFallback',
        );
        return;
      }
      await _deliverPetReply(
        '我這次好像沒有聽清楚，等一下再說一次好嗎？',
        petMode: PetMode.listening,
        toolName: 'sttError',
      );
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
    // 新一輪開始：清掉上一輪的即時寵物字幕，避免殘留在畫面上。
    _liveRealtimeReply = '';
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

  /// Realtime 寵物（assistant）語音字幕的即時更新：寵物說話過程中每段 transcript
  /// 抵達時呼叫，讓字幕跟著聲音逐步顯示。純顯示，不寫入對話紀錄；最終完整文字仍由
  /// [handleRealtimeAssistantReply] 落地並清空這裡的即時文字。
  void updateRealtimeLivePetText(String text) {
    _liveRealtimeReply = text;
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
    _liveRealtimeReply = '';
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
    // 最終完整回覆落地 → 清掉即時逐字字幕，改由這段靜態文字接手顯示。
    _liveRealtimeReply = '';
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
      if (result.errorType == SttErrorType.networkError &&
          profileController.sttMode == SttMode.openAiProxy) {
        // dev / test：保留切回本機 mock 的離線備援，方便沒有後端時繼續開發。
        if (AppConfig.mockServicesEnabled) {
          await profileController.setSttMode(SttMode.mock);
          await _deliverPetReply(
            '連線剛剛不太穩，我先用手機裡的辨識，讓你可以繼續說。',
            petMode: PetMode.listening,
            toolName: 'sttFallback',
          );
          return;
        }
        // 正式版：網路不穩不切 mock、不假成功，用白話請長者稍後再說一次。
        await _deliverPetReply(
          '網路好像不太穩，我這次沒聽清楚，等一下再說一次好嗎？',
          petMode: PetMode.listening,
          toolName: 'sttError',
        );
        return;
      }
      final message = result.message ?? '我剛剛沒有聽清楚，可以再說一次嗎？';
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
        if (navigationIntent.action == NavigationAction.replayOnboarding) {
          coachMarkController?.requestReplay();
        }
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
        history: _recentChatHistory(),
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
      AppLog.debug(
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
