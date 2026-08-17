import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/care_alert.dart';
import '../models/companion_analysis_result.dart';
import '../models/conversation_turn.dart';
import '../models/language_route.dart';
import '../models/pet_status.dart';
import '../models/realtime_timeout.dart';
import '../models/voice_agent_state.dart';
import '../onboarding/coach_mark_controller.dart';
import '../services/ai_navigation_service.dart';
import '../services/app_usage_tracking_service.dart';
import '../services/care_alert_notification_service.dart';
import '../services/companion_engine_service.dart';
import '../services/emotion_services.dart';
import '../services/language_routing_service.dart';
import '../services/realtime_timeout_registry.dart';
import '../services/realtime_turn_coordinator.dart';
import '../services/realtime_voice_service.dart';
import '../services/web_search_service.dart';
import '../utils/app_log.dart';
import '../utils/zh_convert.dart';
import 'app_navigation_controller.dart';
import 'agent_tool_controller.dart';
import 'care_alert_controller.dart';
import 'conversation_controller.dart';
import 'memory_controller.dart';
import 'pet_controller.dart';
import 'pet_stats_controller.dart';
import 'profile_controller.dart';

class VoiceAgentController extends ChangeNotifier with WidgetsBindingObserver {
  VoiceAgentController({
    required this.profileController,
    required this.petController,
    required this.petStatsController,
    required this.conversationController,
    required this.realtimeVoiceService,
    required this.companionEngineService,
    required this.languageRoutingService,
    required this.memoryController,
    required this.navigationService,
    required this.navigationController,
    this.trackingService,
    this.agentToolController,
    this.careAlertController,
    this.careAlertNotificationService,
    this.coachMarkController,
    this.timeoutConfig = const RealtimeTimeoutConfig(),
    this.timeoutPolicy = const RealtimeTimeoutPolicy(),
  }) {
    WidgetsBinding.instance.addObserver(this);
  }

  final ProfileController profileController;
  final PetController petController;
  final PetStatsController petStatsController;
  final ConversationController conversationController;
  final RealtimeVoiceService realtimeVoiceService;
  final CompanionEngineService companionEngineService;
  final LanguageRoutingService languageRoutingService;
  final MemoryController memoryController;
  final AiNavigationService navigationService;
  final AppNavigationController navigationController;
  final AppUsageTrackingService? trackingService;
  final AgentToolController? agentToolController;
  final CareAlertController? careAlertController;
  final CareAlertNotificationService? careAlertNotificationService;
  final CoachMarkController? coachMarkController;
  final RealtimeTimeoutConfig timeoutConfig;
  final RealtimeTimeoutPolicy timeoutPolicy;
  final TextEmotionService _textEmotionService = const TextEmotionService();
  final VoiceFeatureService _voiceFeatureService = const VoiceFeatureService();

  VoiceAgentState _state = VoiceAgentState.idle;
  UserEmotion _emotion = UserEmotion.neutral;
  String _petMood = 'neutral';
  String _petExpression = 'normal';
  String _petAction = 'idle';
  String _lastError = '';
  StreamSubscription<RealtimeVoiceEvent>? _sub;
  String _pendingRealtimeUserText = '';
  String _pendingRealtimeEmotion = 'neutral';
  String _pendingRealtimeTurnId = '';
  // 寵物回覆中才抵達的「本輪使用者 final transcript」去重（同一句可能由
  // transcription.completed 與 conversation.item.done 各送一次）。
  String _lastBackgroundUserTranscript = '';
  String _activeTurnId = '';
  String _responseTurnId = '';
  String _latestCompanionTurnId = '';
  // CR-0089：字幕 / talk 狀態保留到「語音真的播完」才收。
  // _currentTurnHadAudio：本輪是否有播語音（assistantAudioStart 設）。
  // _awaitingAudioStop：response.done 已到、正在等 assistantAudioPlaybackStopped。
  bool _currentTurnHadAudio = false;
  bool _awaitingAudioStop = false;
  Timer? _audioStopFallbackTimer;
  // 安全保底：output_audio_buffer.stopped 漏訊號時的最大等待（非用秒數猜音長）。
  static const Duration _audioStopFallback = Duration(seconds: 15);
  String _lastAlertedTurnId = '';
  String _partialTranscript = '';
  DateTime? _speechStartedAt;
  DateTime? _speechStoppedAt;
  CompanionAnalysisResult? _currentCompanionContext;
  LanguageRouteResult _currentLanguageRoute = const LanguageRouteResult(
    strategyName: 'defaultOpenAiRealtime',
    languageHint: TranscriptLanguageHint.unknown,
    routeReason: 'not_started',
    isFallback: false,
    transcript: '',
  );
  bool _skipNextAssistantText = false;
  int _connectionAttemptId = 0;
  int _transcriptRouteAttemptId = 0;
  bool _isHandlingRealtimeFailure = false;
  bool _isConnecting = false;
  bool _userRequestedRealtime = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 1;
  final RealtimeTurnCoordinator _turnCoordinator = RealtimeTurnCoordinator();
  final RealtimeTimeoutRegistry _timeouts = RealtimeTimeoutRegistry();

  VoiceAgentState get state => _state;
  UserEmotion get emotion => _emotion;
  String get petMood => _petMood;
  String get petExpression => _petExpression;
  String get petAction => _petAction;
  String get lastError => _lastError;
  CompanionAnalysisResult? get currentCompanionContext =>
      _currentCompanionContext;
  LanguageRouteResult get currentLanguageRoute => _currentLanguageRoute;
  String get strategyName => _currentLanguageRoute.strategyName;
  String get languageHint => _currentLanguageRoute.languageHint.value;
  String get routeReason => _currentLanguageRoute.routeReason;
  bool get isLanguageFallback => _currentLanguageRoute.isFallback;
  String get activeTurnId => _activeTurnId;
  String get partialTranscript => _partialTranscript;
  bool get isRealtimeReady =>
      _state != VoiceAgentState.idle &&
      _state != VoiceAgentState.error &&
      _state != VoiceAgentState.recovering;

  /// 連續 Realtime session 的輪次控制核心：只有「未連線」（idle / error）時，
  /// 才能開始一段新的語音對話 / 開始一次新的語音輸入。
  /// 一旦進入 connecting…speaking…recovering 任何進行中的狀態，都視為對話已在進行，
  /// 必須等寵物講完（回到 listening 待命）才可繼續，不可重複開始。
  bool get canStartVoiceInput =>
      _state == VoiceAgentState.idle || _state == VoiceAgentState.error;

  /// 寵物正在回覆中：thinking（思考 / 工具處理）或 speaking（播放語音）。
  /// 此時使用者要說話，必須先「打斷」（barge-in），不可悄悄插入新的一輪。
  bool get isPetResponding =>
      _state == VoiceAgentState.thinking || _state == VoiceAgentState.speaking;

  /// 連續 session 待命中：寵物已準備好聽使用者說話，可直接開口（server VAD 接住）。
  bool get isAwaitingUserSpeech =>
      _state == VoiceAgentState.ready || _state == VoiceAgentState.listening;

  /// CR-0096：正在收使用者這一輪語音（待命聆聽 ready/listening，或已在串流 partial
  /// transcript 的 transcribing）。這些狀態下按一下按鈕＝「停止收音並送出本輪語音」。
  /// 不含 thinking/speaking（寵物回覆中）與 connecting/recovering（連線中）。
  bool get isCapturingUserSpeech =>
      _state == VoiceAgentState.ready ||
      _state == VoiceAgentState.listening ||
      _state == VoiceAgentState.transcribing;

  /// Turn-based：是否已經在處理某一輪的寵物回覆（已收下使用者這句、正在生成 / 播放回覆）。
  ///
  /// 用來在「寵物回覆中」阻擋後續使用者語音事件與 server VAD 觸發的 listening /
  /// transcribing 狀態切換。刻意用 [_activeTurnId] 是否已設定（而不是 thinking 狀態）
  /// 來判斷：因為「使用者剛說完、final transcript 還沒被收下」的那一刻 server 也會送
  /// thinking，但那一句必須被正常處理，不能誤擋。一旦 final transcript 收下（turnId
  /// 設定）或寵物已在 speaking，才視為這一輪回覆進行中。
  bool get _petReplyInProgress =>
      _activeTurnId.isNotEmpty || _state == VoiceAgentState.speaking;

  /// Turn-based：目前是否已有一條可用的 Realtime 連線（寵物說完回到 idle 後仍保留）。
  /// 用來判斷「按鈕」要開新 session 重連，或只是同一條連線開始下一句。
  bool get hasOpenRealtimeSession => realtimeVoiceService.isConnectionUsable;
  RealtimeFailureType get lastFailureType =>
      realtimeVoiceService.lastFailureType;
  String get backendHealthMessage {
    final health = realtimeVoiceService.lastHealthStatus;
    if (health == null) return '尚未檢查';
    if (!health.ok) return health.message.isEmpty ? '後端未啟動' : health.message;
    if (!health.hasOpenAiKey) return 'OpenAI API Key 未設定';
    return 'OK';
  }

  Future<void> startRealtimeConversation() async {
    _userRequestedRealtime = true;
    // Turn-based：上一句寵物說完後回到 idle，但同一條 Realtime 連線仍在。
    // 此時再次按鈕＝開始「下一句」：只恢復麥克風 + 重新待命聆聽，
    // **不重連、不重建 SDP、不另開 session**，維持對話脈絡連續。
    if (_state == VoiceAgentState.idle &&
        !_isConnecting &&
        realtimeVoiceService.isConnectionUsable) {
      realtimeVoiceService.resumeMicInput();
      await realtimeVoiceService.startListening();
      _transition(VoiceAgentState.listening, 'turn_based_next_turn');
      return;
    }
    if (_isConnecting || realtimeVoiceService.isConnecting) {
      return;
    }
    // 連續 session 模型：只要不是 idle / error（＝已連線或對話進行中），
    // 就代表語音輪次已在進行，不可重複開始一段新的。
    // 涵蓋 connecting / ready / listening / transcribing / thinking / speaking /
    // recovering——避免使用者在寵物還沒講完時又觸發新的語音輸入造成混亂。
    if (!canStartVoiceInput) {
      if (!realtimeVoiceService.isConnectionUsable) {
        _handleRealtimeRecoverableFailure('active_connection_unusable');
      }
      return;
    }
    final attemptId = ++_connectionAttemptId;
    _isConnecting = true;
    _reconnectAttempts = 0;
    _lastError = '';
    _currentLanguageRoute = _realtimeStartRoute();
    _sub?.cancel();
    _sub = realtimeVoiceService.events.listen(_handleRealtimeEvent);
    try {
      final health = await realtimeVoiceService.checkBackendHealth(
        AppConfig.healthUrlForSttProxy(profileController.sttProxyUrl),
      );
      if (attemptId != _connectionAttemptId) return;
      if (!health.ok || !health.hasOpenAiKey) {
        final type = !health.ok
            ? RealtimeFailureType.backendUnavailable
            : RealtimeFailureType.missingApiKey;
        _lastError = type.message;
        _transition(VoiceAgentState.error, type.name);
        petController.setModeAndMessage(PetMode.sad, type.message);
        conversationController.showPetBubbleMessage(type.message);
        return;
      }

      _transition(VoiceAgentState.connecting, 'connect_started');
      _startTimeout(RealtimeTimeoutType.connectionTimeout);
      petController.setMessage('正在連線陪伴寵物');
      conversationController.showPetBubbleMessage('正在連線陪伴寵物');
      notifyListeners();
      debugPrint('[PET_NAME] current=${profileController.petName}');
      await realtimeVoiceService.connect(
        realtimeCallUrl:
            AppConfig.realtimeCallUrlForSttProxy(profileController.sttProxyUrl),
        petName: profileController.petName,
        userId: memoryController.userId,
        companionContext: _companionContextPrompt(),
        languageHint: _currentLanguageRoute.languageHint.value,
        replyLanguage: _currentLanguageRoute.replyLanguage.value,
        mode: profileController.voiceLanguageMode ==
                VoiceLanguageMode.taigiRealtime
            ? 'taigi_realtime'
            : '',
      );
      if (attemptId != _connectionAttemptId ||
          _state == VoiceAgentState.idle ||
          _state == VoiceAgentState.recovering) {
        debugPrint(
          '[VoiceAgentController] ignore stale connect completion attempt=$attemptId active=$_connectionAttemptId',
        );
        return;
      }
      await realtimeVoiceService.startListening();
      _cancelTimeout(RealtimeTimeoutType.connectionTimeout);
    } catch (error) {
      await _handleRealtimeFailure(error);
    } finally {
      if (attemptId == _connectionAttemptId) {
        _isConnecting = false;
      }
    }
  }

  /// 在 Realtime 語音 session 連線中時，把使用者打字的文字注入「同一個」live session，
  /// 讓寵物用語音在同一段對話裡回覆（而不是另外走 quickAction 產生平行回覆）。
  ///
  /// 回傳值語意：
  /// - `true`：Realtime 已接手這句文字（已顯示使用者氣泡、已記錄 user turn、
  ///   已透過 data channel 送出文字並觸發回覆）。UI 端不需再做任何事。
  /// - `false`：Realtime 目前不可用（idle/error/recovering，或 data channel 未開），
  ///   代表「沒接手」，UI 端應自行 fallback 回 quickAction。
  Future<bool> sendTextDuringRealtime(String text) async {
    final normalized = text.trim();
    if (normalized.isEmpty) return false;
    if (!isRealtimeReady || !realtimeVoiceService.isConnectionUsable) {
      return false;
    }

    final decision = _turnCoordinator.acceptFinalTranscript(normalized);
    if (!decision.accepted) {
      // 同一句重複送出或目前已有未完成的 turn 在跑時，不重複注入，
      // 但仍視為「已接手」避免 UI 退回 quickAction 產生平行回覆。
      debugPrint(
        '[VoiceAgentController] typed text rejected by turn coordinator reason=${decision.reason}',
      );
      return true;
    }
    final transcript = decision.transcript;
    final turnId = decision.turnId;
    _cancelTurnTimeouts();

    // 與語音 final transcript 一致：顯示使用者氣泡、記錄 user turn，
    // 確保接下來的寵物回覆能配對到同一個 turn 並寫進同一個 session 的對話紀錄。
    conversationController.commitRealtimeFinalTranscript(
      transcript,
      awaitingPetReply: true,
    );
    _activeTurnId = turnId;
    _partialTranscript = '';
    _pendingRealtimeTurnId = turnId;
    _latestCompanionTurnId = turnId;

    _emotion = detectEmotion(transcript);
    _pendingRealtimeUserText = transcript;
    _pendingRealtimeEmotion = _emotion.name;
    _applyEmotionToPet();
    conversationController.appendExternalTurn(
      ConversationTurn(
        timestamp: DateTime.now(),
        userText: transcript,
        petReply: '',
        toolName: 'realtime-user-text',
        turnId: turnId,
        emotionTag: _emotion.name,
        asrSource: _currentLanguageRoute.strategyName,
        languageHint: _currentLanguageRoute.languageHint.value,
        routeReason: _currentLanguageRoute.routeReason,
        replyLanguage: _currentLanguageRoute.replyLanguage.value,
      ),
    );

    _transition(
      VoiceAgentState.thinking,
      'typed_text_injected',
      turnId: turnId,
    );
    _startTimeout(RealtimeTimeoutType.responseTimeout, turnId: turnId);
    unawaited(_analyzeCompanionTranscript(transcript, turnId));

    await realtimeVoiceService.sendUserText(transcript);
    notifyListeners();
    return true;
  }

  Future<void> stopRealtimeConversation() async {
    _userRequestedRealtime = false;
    _isConnecting = false;
    _reconnectAttempts = 0;
    _cancelAllTimeouts();
    await realtimeVoiceService.stop();
    _lastError = '';
    _activeTurnId = '';
    _responseTurnId = '';
    _partialTranscript = '';
    _speechStartedAt = null;
    _speechStoppedAt = null;
    _turnCoordinator.reset();
    conversationController.clearRealtimeTranscriptState();
    _transition(VoiceAgentState.idle, 'manual_stop');
    petController.setMessage('我先在旁邊陪你。想不到要聊什麼也沒關係，要不要跟我說說今天最舒服的一刻？');
  }

  /// CR-0096：聆聽中按一下「送出」——停止收音並把這一輪語音送出讓寵物回覆。
  ///
  /// 與 [stopRealtimeConversation]（結束整段對話、回 idle、清掉 transcript）語意明確區分：
  /// 這裡**不取消、不斷線、不清空 transcript**，而是 commit 本輪語音 + 請求回覆，
  /// 讓吵雜環境下使用者不必等 server VAD 自動判斷靜音，自己按一下就能結束說話並得到回覆。
  ///
  /// 只有這一輪「確實有語音」（已收到 user speech started，或已有 partial transcript）時才
  /// 送出，避免空 buffer 觸發 `input_audio_buffer_commit_empty`；送出後進入 thinking
  /// （UI 顯示「想一下」）並掛 responseTimeout，確保萬一沒回覆也不會卡死。
  Future<void> stopListeningAndSubmit() async {
    if (!isCapturingUserSpeech) return;
    final hasSpeech =
        _speechStartedAt != null || _partialTranscript.trim().isNotEmpty;
    if (!hasSpeech) {
      // 使用者按了按鈕但這一輪還沒開口：不送空 commit，維持待命聆聽，等使用者開口。
      debugPrint('[VOICE_TURN] manual stop ignored: no speech captured yet');
      return;
    }
    // 暫停麥克風 + commit 本輪語音 + （無 active response 時）請求回覆。
    await realtimeVoiceService.commitUserAudioAndRespond();
    // 進入處理中：保留 _speechStartedAt / transcript 狀態，等 final transcript 與
    // response 照既有事件流程接續處理（會重設帶 turnId 的 responseTimeout）。
    _transition(VoiceAgentState.thinking, 'manual_stop_submit');
    _startTimeout(RealtimeTimeoutType.responseTimeout);
  }

  /// Turn-based：寵物回覆中（thinking / speaking）**不可被打斷**。
  ///
  /// 為了讓長者陪伴對話穩定（咳嗽、嗯一聲、背景音都不該中斷寵物），這裡一律
  /// 不動作、不送 `response.cancel`、不改狀態，回傳 `false` 代表「沒有打斷」。
  /// 使用者要說下一句，必須等寵物說完、回到 idle 後再按一次語音按鈕。
  ///
  /// 保留此方法只為相容既有呼叫點與測試；不再從 UI 觸發打斷。
  Future<bool> interruptPetForUserTurn() async {
    debugPrint(
        '[VOICE_TURN] barge-in disabled (turn-based); pet finishes first');
    return false;
  }

  void _handleRealtimeEvent(RealtimeVoiceEvent event) {
    // Turn-based 防護：寵物這一輪回覆進行中時，一律忽略使用者語音相關事件。
    // 麥克風雖已暫停，這裡再做一層阻擋，確保任何殘留的咳嗽 / 雜音 event 都不會
    // 觸發下一輪輸入或打斷寵物（即使技術上無法完全關閉 mic 也安全）。
    if (_petReplyInProgress &&
        (event.type == RealtimeEventType.userSpeechStarted ||
            event.type == RealtimeEventType.userSpeechStopped ||
            event.type == RealtimeEventType.partialTranscript ||
            event.type == RealtimeEventType.finalTranscript)) {
      // server VAD 設了 create_response，寵物常在「使用者這句轉錄完成」前就先開口，
      // 導致本輪 final transcript 比 response 晚到。這筆是使用者自己這句、不是插話，
      // 仍要記錄對話 + 送分析（情緒 / 長期記憶 / Care Alert），但**不打斷寵物、
      // 不重新觸發回覆**。其餘（新插話 / 雜音 / partial）照舊忽略。
      if (event.type == RealtimeEventType.finalTranscript) {
        _cancelTimeout(RealtimeTimeoutType.transcriptTimeout);
        unawaited(_captureUserTranscriptDuringPetReply(event.payload));
        return;
      }
      debugPrint(
        '[VOICE_TURN] ignore user speech event ${event.type.name} while pet reply in progress',
      );
      return;
    }
    switch (event.type) {
      case RealtimeEventType.state:
        _applyStateFromPayload(event.payload);
        break;
      case RealtimeEventType.userSpeechStarted:
        _speechStartedAt = DateTime.now();
        _speechStoppedAt = null;
        _partialTranscript = '';
        conversationController.beginRealtimeUserSpeech();
        _startTimeout(RealtimeTimeoutType.transcriptTimeout);
        break;
      case RealtimeEventType.userSpeechStopped:
        _speechStoppedAt = DateTime.now();
        conversationController.markAwaitingFinalTranscript();
        _startTimeout(RealtimeTimeoutType.transcriptTimeout);
        break;
      case RealtimeEventType.partialTranscript:
        _partialTranscript = event.payload.trim();
        conversationController.updateRealtimePartialTranscript(
          _partialTranscript,
        );
        _transition(
          VoiceAgentState.transcribing,
          'partial_transcript_received',
          notify: false,
        );
        notifyListeners();
        break;
      case RealtimeEventType.finalTranscript:
        _cancelTimeout(RealtimeTimeoutType.transcriptTimeout);
        unawaited(_handleFinalTranscript(event.payload));
        break;
      case RealtimeEventType.assistantResponseStart:
        _responseTurnId = _activeTurnId;
        _currentTurnHadAudio = false; // CR-0089：新一輪重置「是否有語音」。
        _startTimeout(
          RealtimeTimeoutType.responseTimeout,
          turnId: _responseTurnId,
        );
        _transition(
          VoiceAgentState.thinking,
          'realtime_response_started',
          turnId: _responseTurnId,
        );
        break;
      case RealtimeEventType.assistantResponseDone:
        _cancelTimeout(RealtimeTimeoutType.responseTimeout);
        if (_responseTurnId.isNotEmpty && !_isActiveTurn(_responseTurnId)) {
          debugPrint(
            '[VoiceAgentController] drop stale response.done turn=$_responseTurnId active=$_activeTurnId',
          );
          return;
        }
        // CR-0089：response.done ≠ 語音播完。若本輪有語音，保留 talk / 字幕，
        // 等 assistantAudioPlaybackStopped 才收 turn（純文字回覆則照舊立即收）。
        _requestFinishPetTurn('realtime_response_done');
        break;
      case RealtimeEventType.assistantText:
        if (_skipNextAssistantText) {
          _skipNextAssistantText = false;
          return;
        }
        // Always show the latest assistant text even if the user started a
        // new turn before OpenAI's previous response landed — OpenAI's reply
        // is the most recent meaningful content and dropping it leaves the
        // bubble empty.
        final responseTurnId =
            _responseTurnId.isEmpty ? _pendingRealtimeTurnId : _responseTurnId;
        // 寵物回覆已指示用繁體，這裡再保險轉一次，確保對話紀錄全繁體。
        final assistantReply = toTraditional(event.payload);
        unawaited(petStatsController.markRealtimeConversationCompleted());
        conversationController.handleRealtimeAssistantReply(
          assistantReply,
          turnId: responseTurnId,
        );
        if (_pendingRealtimeUserText.isNotEmpty &&
            _pendingRealtimeTurnId.isNotEmpty) {
          unawaited(
            memoryController.extractMemory(
              sessionId: conversationController.activeSessionId,
              turnId: _pendingRealtimeTurnId,
              userText: _pendingRealtimeUserText,
              aiReply: assistantReply.trim(),
              emotion: _pendingRealtimeEmotion,
            ),
          );
        }
        break;
      case RealtimeEventType.assistantPartialText:
        // 即時逐字字幕：寵物說話過程中跟著聲音更新顯示文字，純顯示用，
        // 不記錄對話、不抽取記憶、不改寵物狀態（那些只在最終 assistantText 處理）。
        // 若這一輪寵物文字被刻意抑制（導頁 / 改名等 _skipNextAssistantText），
        // 連帶不顯示 partial；不在這裡重置旗標（由最終 assistantText 重置）。
        if (_skipNextAssistantText) {
          break;
        }
        conversationController
            .updateRealtimeLivePetText(toTraditional(event.payload));
        break;
      case RealtimeEventType.assistantAudioStart:
        _responseTurnId =
            _responseTurnId.isEmpty ? _activeTurnId : _responseTurnId;
        _transition(
          VoiceAgentState.speaking,
          'speaking_started',
          turnId: _responseTurnId,
        );
        break;
      case RealtimeEventType.assistantAudioPlaybackStarted:
        // CR-0089：本輪有「真實語音」（非純文字）→ 收 turn 要等語音真的播完。
        // 不在 assistantAudioStart 設，因為那連純文字回覆也會觸發。
        _currentTurnHadAudio = true;
        break;
      case RealtimeEventType.assistantAudioEnd:
        _cancelTimeout(RealtimeTimeoutType.responseTimeout);
        // CR-0089：assistantAudioEnd 在 response.done 時發出（語音可能還在播），
        // 不在此直接收 turn；交給 _requestFinishPetTurn 決定立即收或等播完。
        _requestFinishPetTurn('speaking_completed');
        break;
      case RealtimeEventType.assistantAudioPlaybackStopped:
        // CR-0089：語音「真的播完」。此時才把 talk 狀態 / 字幕收掉。
        _audioStopFallbackTimer?.cancel();
        _audioStopFallbackTimer = null;
        if (_awaitingAudioStop || _state == VoiceAgentState.speaking) {
          _finishPetTurn('audio_playback_stopped');
        }
        break;
      case RealtimeEventType.dataChannelOpen:
        _cancelTimeout(RealtimeTimeoutType.connectionTimeout);
        _cancelTimeout(RealtimeTimeoutType.reconnectTimeout);
        _isConnecting = false;
        _transition(VoiceAgentState.listening, 'data_channel_open');
        break;
      case RealtimeEventType.dataChannelClosed:
        _handleRealtimeRecoverableFailure('data_channel_closed');
        break;
      case RealtimeEventType.peerConnectionFailed:
        _handleRealtimeRecoverableFailure('peer_connection_failed');
        break;
      case RealtimeEventType.error:
        unawaited(_handleRealtimeFailure(event.payload));
        break;
    }
  }

  void _applyStateFromPayload(String value) {
    if (value == 'idle' && _state == VoiceAgentState.error) {
      return;
    }
    final mapped = switch (value) {
      'connecting' => VoiceAgentState.connecting,
      'connected' || 'ready' => VoiceAgentState.ready,
      'listening' => VoiceAgentState.listening,
      'transcribing' => VoiceAgentState.transcribing,
      'thinking' => VoiceAgentState.thinking,
      'speaking' => VoiceAgentState.speaking,
      'recovering' => VoiceAgentState.recovering,
      _ => VoiceAgentState.idle,
    };
    // Turn-based：寵物回覆進行中時，server VAD 因使用者出聲而送來的
    // listening / transcribing 一律忽略——不讓咳嗽 / 雜音把寵物從回覆中拉走。
    // （寵物自身的 thinking / speaking 狀態事件不受影響，照常套用。）
    if (_petReplyInProgress &&
        (mapped == VoiceAgentState.listening ||
            mapped == VoiceAgentState.transcribing)) {
      debugPrint(
        '[VOICE_TURN] ignore VAD state=$value while pet reply in progress',
      );
      return;
    }
    if (mapped == VoiceAgentState.ready ||
        mapped == VoiceAgentState.listening) {
      _cancelTimeout(RealtimeTimeoutType.connectionTimeout);
      _cancelTimeout(RealtimeTimeoutType.reconnectTimeout);
    }
    _transition(mapped, 'service_state_$value');
  }

  Future<void> _handleFinalTranscript(String realtimeTranscript) async {
    // Realtime 轉錄常回簡體；顯示與送後端前先統一轉台灣繁體。
    final normalizedRealtimeTranscript =
        toTraditional(realtimeTranscript.trim());
    if (normalizedRealtimeTranscript.isEmpty) {
      _partialTranscript = '';
      conversationController.clearRealtimeTranscriptState();
      return;
    }
    final routeAttemptId = ++_transcriptRouteAttemptId;
    final route = await languageRoutingService.routeTranscript(
      mode: profileController.voiceLanguageMode,
      manualStrategyName: profileController.manualAsrStrategy,
      realtimeTranscript: normalizedRealtimeTranscript,
    );
    if (routeAttemptId != _transcriptRouteAttemptId) {
      debugPrint(
        '[LANGUAGE_ROUTE] ignore stale route attempt=$routeAttemptId active=$_transcriptRouteAttemptId',
      );
      return;
    }
    _currentLanguageRoute = route;
    if (route.isFallback) {
      debugPrint(
        '[LANGUAGE_ROUTE] fallback strategy=${route.strategyName} reason=${route.routeReason}',
      );
    } else {
      debugPrint(
        '[LANGUAGE_ROUTE] strategy=${route.strategyName} language=${route.languageHint.value} reason=${route.routeReason}',
      );
    }

    final decision = _turnCoordinator.acceptFinalTranscript(route.transcript);
    if (!decision.accepted) {
      conversationController.clearRealtimeTranscriptState();
      debugPrint(
        '[VoiceAgentController] ignore transcript reason=${decision.reason} route=${route.routeReason}',
      );
      notifyListeners();
      return;
    }
    final transcript = decision.transcript;
    final turnId = decision.turnId;
    _cancelTurnTimeouts();
    conversationController.commitRealtimeFinalTranscript(
      transcript,
      awaitingPetReply: true,
    );
    _activeTurnId = turnId;
    _partialTranscript = '';
    _pendingRealtimeTurnId = turnId;
    _latestCompanionTurnId = turnId;
    _transition(
      VoiceAgentState.thinking,
      'final_transcript_received',
      turnId: turnId,
    );
    _startTimeout(RealtimeTimeoutType.responseTimeout, turnId: turnId);
    unawaited(_analyzeCompanionTranscript(transcript, turnId));

    final navigationIntent = navigationService.detect(transcript);
    if (navigationIntent != null) {
      if (!_isActiveTurn(turnId)) return;
      navigationController.navigateTo(navigationIntent.route);
      if (navigationIntent.action == NavigationAction.replayOnboarding) {
        coachMarkController?.requestReplay();
      }
      unawaited(
        trackingService?.track(
              'voice_navigation',
              sessionId: conversationController.activeSessionId,
              metadata: {
                'route': navigationIntent.route,
                'source': 'realtime_voice',
                'languageHint': _currentLanguageRoute.languageHint.value,
              },
            ) ??
            Future<bool>.value(false),
      );
      petController.setMessage(navigationIntent.reply);
      conversationController.appendExternalTurn(
        ConversationTurn(
          timestamp: DateTime.now(),
          userText: transcript,
          petReply: navigationIntent.reply,
          toolName: 'navigation',
          turnId: turnId,
          emotionTag: UserEmotion.neutral.name,
          asrSource: _currentLanguageRoute.strategyName,
          languageHint: _currentLanguageRoute.languageHint.value,
          routeReason: _currentLanguageRoute.routeReason,
          replyLanguage: _currentLanguageRoute.replyLanguage.value,
        ),
      );
      _pendingRealtimeUserText = '';
      _skipNextAssistantText = true;
      notifyListeners();
      return;
    }
    // 工具路由（本地指令 XOR 後端 agent；含查詢結果語音回應）。主流程與「寵物回覆中擷取」
    // 共用同一條，確保不論何時說指令都會被理解與執行。Fall through：Realtime 仍照常回覆。
    _routeToolsForTranscript(transcript, turnId);
    final renameResult = _tryHandleRenameIntent(transcript);
    _emotion = detectEmotion(transcript);
    AppLog.debug(
      '[EMOTION] text=${AppLog.previewTranscript(transcript)} '
      'emotion=${_emotion.name}',
    );
    _pendingRealtimeUserText = transcript;
    _pendingRealtimeEmotion = _emotion.name;
    _applyEmotionToPet();
    conversationController.appendExternalTurn(
      ConversationTurn(
        timestamp: DateTime.now(),
        userText: transcript,
        petReply: renameResult.reply ?? '',
        toolName: renameResult.handled ? 'renamePet' : 'realtime-user',
        turnId: turnId,
        emotionTag: _emotion.name,
        asrSource: _currentLanguageRoute.strategyName,
        languageHint: _currentLanguageRoute.languageHint.value,
        routeReason: _currentLanguageRoute.routeReason,
        replyLanguage: _currentLanguageRoute.replyLanguage.value,
      ),
    );
    if (renameResult.reply != null) {
      unawaited(
        conversationController.handleRealtimeAssistantReply(
          renameResult.reply!,
          turnId: turnId,
        ),
      );
    }
    notifyListeners();
  }

  LanguageRouteResult _realtimeStartRoute() {
    if (profileController.voiceLanguageMode ==
        VoiceLanguageMode.taigiRealtime) {
      return const LanguageRouteResult(
        strategyName: 'openai-realtime',
        languageHint: TranscriptLanguageHint.taigi,
        routeReason: 'taigi_realtime_mode',
        isFallback: false,
        transcript: '',
        replyLanguage: ReplyLanguage.mixedZhTaigi,
      );
    }
    return const LanguageRouteResult(
      strategyName: 'defaultOpenAiRealtime',
      languageHint: TranscriptLanguageHint.zh,
      routeReason: 'default_openai_realtime',
      isFallback: false,
      transcript: '',
      replyLanguage: ReplyLanguage.zhTw,
    );
  }

  Future<void> _handleLocalRealtimeCommand(String text, String turnId) async {
    try {
      // 本地工具路由（簽到 / 設定 / 找新聞 / 查資訊…）。
      final result = await conversationController.toolRouter.route(text);
      // 需要把結果說給使用者聽的工具（找新聞 / 查資訊等 shouldSpeak=true）→ 用寵物的
      // 聲音把結果念出來，使用者才知道有查到（不再「沒聽懂」）。speakToolOutcome 會等
      // 寵物把當下回覆講完再念，不會與正在播放的回覆撞在一起。
      if (result.shouldSpeak && result.message.trim().isNotEmpty) {
        unawaited(realtimeVoiceService.speakToolOutcome(result.message.trim()));
      }
    } catch (_) {}
  }

  /// 寵物回覆進行中才抵達的「本輪使用者 final transcript」的旁路處理。
  ///
  /// server VAD 的 `create_response` 讓寵物常在使用者這句轉錄完成前就先開口，導致
  /// 本輪 final transcript 比 response 晚到、被 turn-based 守衛擋掉，連帶讓對話紀錄
  /// 的使用者文字空白、情緒/長期記憶/Care Alert 全失效。這裡把這筆「使用者自己的話」
  /// 接住：設定待配對欄位、設定 `_latestUserText`（讓寵物回覆落地時配對成完整一筆，
  /// 不會空白也不重複），並送 companion 分析（情緒 / 後端長期記憶 / Care Alert）。
  /// 刻意**不改語音狀態機、不路由工具 / 導頁、不重新觸發寵物回覆、不清掉寵物正在
  /// 播放的回覆泡泡**——只做旁路記錄與分析。
  Future<void> _captureUserTranscriptDuringPetReply(
    String realtimeTranscript,
  ) async {
    // 同上：背景接住的使用者句也統一轉繁體再顯示 / 分析 / 記憶。
    final transcript = toTraditional(realtimeTranscript.trim());
    if (transcript.isEmpty) return;
    // 同一句去重（transcription.completed 與 conversation.item.done 可能各送一次）。
    if (transcript == _lastBackgroundUserTranscript) return;
    _lastBackgroundUserTranscript = transcript;

    final turnId = _pendingRealtimeTurnId.isNotEmpty
        ? _pendingRealtimeTurnId
        : 'rt_bg_${DateTime.now().microsecondsSinceEpoch}';
    _pendingRealtimeTurnId = turnId;
    _pendingRealtimeUserText = transcript;
    _emotion = detectEmotion(transcript);
    _pendingRealtimeEmotion = _emotion.name;
    _latestCompanionTurnId = turnId;

    // 設定 _latestUserText（不另外新增 turn、不清掉寵物正在播放的回覆）→ 等寵物回覆
    // 落地（assistantText）時，handleRealtimeAssistantReply 會配對成「使用者這句 +
    // 寵物回覆」一筆完整紀錄。
    conversationController.showUserBubbleMessage(
      transcript,
      awaitingPetReply: true,
      clearPetReply: false,
    );

    debugPrint(
      '[VOICE_TURN] capture user final during pet reply turn=$turnId text="$transcript"',
    );
    // 指令也可能在寵物還在回覆時說出來（例如「幫我找新聞」）。先前這條路徑只做情緒分析、
    // 不判斷工具，導致使用者覺得「沒聽懂」。這裡也跑一次工具路由 + 語音回應，讓「不管何時
    // 說指令都聽得懂」。純附加，不改語音狀態機、不打斷正在播放的回覆。
    _routeToolsForTranscript(transcript, turnId);
    unawaited(
      _analyzeCompanionTranscript(transcript, turnId, applyPetState: false),
    );
    notifyListeners();
  }

  /// 對一句使用者轉錄做「工具路由 + 語音回應」：
  /// - 後端 agent 路由（播音樂 / 打電話 / 查詢…）→ 完成後用語音念出結果 / 確認問句。
  /// - 本地指令路由（簽到 / 設定 / 找新聞 / 查資訊…）→ 需要時用語音念出結果。
  /// 主流程與「寵物回覆中擷取」路徑共用，確保不管何時說指令都會被理解與執行。
  void _routeToolsForTranscript(String transcript, String turnId) {
    if (_tryHandlePendingToolVoiceDecision(transcript)) {
      return;
    }
    if (_isBroadMusicRequest(transcript)) {
      unawaited(
        realtimeVoiceService.speakToolOutcome('想聽誰的歌，還是想聽什麼類型呢？'),
      );
      return;
    }
    if (WebSearchService.isBroadNewsRequest(transcript)) {
      unawaited(
        realtimeVoiceService.speakToolOutcome('你想聽哪一類新聞呢？像是健康、防詐、地方，還是國際新聞？'),
      );
      return;
    }
    // 本地能處理（簽到 / 設定 / 找新聞 / 查資訊…）就走本地，並念出結果；走本地就不再
    // 交給後端 agent，避免同一個指令被執行兩次（重複查 / 重複念）。
    if (conversationController.shouldHandleAsLocalCommand(transcript)) {
      unawaited(_handleLocalRealtimeCommand(transcript, turnId));
      return;
    }
    // 其餘（播音樂 / 打電話 / 其他工具）交給後端 agent 路由，完成後用語音念出結果或確認問句。
    final routing = agentToolController?.routeFromUserText(
      transcript,
      sessionId: conversationController.activeSessionId,
      turnId: turnId,
      petName: profileController.petName,
      emotion: _pendingRealtimeEmotion,
      languageHint: _currentLanguageRoute.languageHint.value,
      petState: {
        'mood': petController.mood,
        'expression': petController.expression,
        'intimacy': petStatsController.intimacy,
        'hunger': petStatsController.fullness,
        'energy': petStatsController.moodValue,
      },
      recentTurns: conversationController.history.take(4).map((turn) {
        return {
          'userText': turn.userText,
          'petReply': turn.petReply,
          'emotionTag': turn.emotionTag,
        };
      }).toList(),
    );
    if (routing != null) {
      unawaited(routing.then((_) => _maybeSpeakToolOutcome()));
    }
  }

  static bool _isBroadMusicRequest(String text) {
    final normalized = text.replaceAll(RegExp(r'[\s，。！？!?、,.]'), '').trim();
    if (normalized.isEmpty) return false;
    if (RegExp(
      r'台語|老歌|放鬆|白噪音|輕音樂|雨聲|助眠|懷舊|自然音|歌手|周杰倫|江蕙|鄧麗君|費玉清|蔡琴|五月天|鳳飛飛|望春風|雨夜花|月亮代表我的心',
    ).hasMatch(normalized)) {
      return false;
    }
    return RegExp(
      r'^(幫我|我想|我欲|想|欲|請)?(播放|放|播|聽)?(一點|一些)?(音樂|歌|歌曲)(予我聽|給我聽|來聽|一下)?[吧嗎呢啦喔]*$',
    ).hasMatch(normalized);
  }

  bool _tryHandlePendingToolVoiceDecision(String transcript) {
    final controller = agentToolController;
    final pending = controller?.pendingIntent;
    if (controller == null ||
        pending == null ||
        !pending.requiresConfirmation) {
      return false;
    }
    final text = transcript.trim();
    if (_isVoiceToolCancel(text)) {
      controller.cancelIntent();
      unawaited(realtimeVoiceService.speakToolOutcome('好，這個動作先取消。'));
      return true;
    }
    if (_isVoiceToolConfirm(text)) {
      unawaited(
        controller.confirmAndExecute().then((_) => _maybeSpeakToolOutcome()),
      );
      return true;
    }
    return false;
  }

  bool _isVoiceToolConfirm(String text) {
    final compact = text.replaceAll(RegExp(r'[\s，,。.!！?？~～]'), '');
    if (compact.isEmpty) return false;
    return RegExp(
            r'^(好|好啊|好喔|好確認|好確定|可以|對|是|嗯|嗯嗯|確認|確定|執行|幫我|麻煩你|好麻煩你|好幫我|可以幫我|著|賀|好啦)$')
        .hasMatch(compact);
  }

  bool _isVoiceToolCancel(String text) {
    final compact = text.replaceAll(RegExp(r'[\s，,。.!！?？~～]'), '');
    if (compact.isEmpty) return false;
    return RegExp(r'^(不要|不用|免|先不要|先不用|取消|算了|毋免|袂使|不用了|不要了|先免)$')
        .hasMatch(compact);
  }

  Future<void> _analyzeCompanionTranscript(
    String transcript,
    String turnId, {
    bool applyPetState = true,
  }) async {
    try {
      final result = await companionEngineService.analyze(
        sttProxyUrl: profileController.sttProxyUrl,
        userId: memoryController.userId,
        sessionId: conversationController.activeSessionId,
        turnId: turnId,
        petName: profileController.petName,
        transcript: transcript,
        languageHint: _currentLanguageRoute.languageHint.value,
        audioFeatures: _estimateAudioFeatures(transcript),
        petState: {
          'mood': petController.mood,
          'expression': petController.expression,
          'intimacy': petStatsController.intimacy,
          'hunger': petStatsController.fullness,
          'energy': petStatsController.moodValue,
        },
        recentTurns: conversationController.history.take(4).map((turn) {
          return {
            'userText': turn.userText,
            'petReply': turn.petReply,
            'emotionTag': turn.emotionTag,
          };
        }).toList(),
      );
      if (result == null) {
        _applyLocalCompanionFallback(transcript, turnId);
        return;
      }
      if (result.turnId != _latestCompanionTurnId ||
          turnId != _latestCompanionTurnId) {
        return;
      }
      _currentCompanionContext = result;
      _maybeCreateCareAlert(result, transcript, turnId);
      // 背景捕捉（寵物正在回覆同一句的轉錄）時不動寵物表情 / 狀態 / 即時 session
      // context，避免打斷正在播放的回覆；情緒與記憶配對已在捕捉端用本地分析設好。
      if (applyPetState) {
        _emotion = _emotionFromEngine(result.emotion);
        _pendingRealtimeEmotion = result.emotion;
        _applyCompanionPetState(result);
        unawaited(realtimeVoiceService.updateCompanionContext(
          _companionContextPrompt(result),
        ));
      }
      debugPrint(
        '[COMPANION_ENGINE] turn=$turnId emotion=${result.emotion} need=${result.companionNeed} strategy=${result.replyStrategy}',
      );
      notifyListeners();
    } catch (error) {
      debugPrint('[COMPANION_ENGINE] fallback: $error');
      _applyLocalCompanionFallback(transcript, turnId);
    }
  }

  /// 生活工具（找新聞 / 播音樂等）在語音模式自動執行後，讓寵物用語音把結果念出來，
  /// 使用者才不會覺得寵物沒聽懂。只處理「已成功執行的低風險工具」；需使用者確認的高影響
  /// 工具仍走確認 UI，不在此自動朗讀。純附加，不影響 Realtime 連線 / SDP / 純語音主流程。
  void _maybeSpeakToolOutcome() {
    final controller = agentToolController;
    if (controller == null) return;
    // 1) 低風險工具（找新聞 / 播音樂…）已自動執行 → 用語音念出結果。
    final result = controller.executionResult;
    if (result != null && result.success) {
      final line = result.message.trim();
      if (line.isNotEmpty) {
        unawaited(realtimeVoiceService.speakToolOutcome(line));
      }
      return;
    }
    // 2) 需確認的高影響工具（打電話 / 傳訊息…）不自動執行 → 用語音念出確認問句，
    //    讓寵物有回應；實際動作仍由確認 UI 完成（安全閘門不變）。
    final pending = controller.pendingIntent;
    if (pending != null && pending.requiresConfirmation) {
      final ask = pending.userFacingMessage.trim();
      if (ask.isNotEmpty) {
        unawaited(realtimeVoiceService.speakToolOutcome(ask));
      }
    }
  }

  /// 旁路記錄：companion 分析判定需要人為關懷時，建立一筆 CareAlert。
  /// 純附加式，不影響 Realtime 狀態機、SDP、DataChannel 或對話流程。
  void _maybeCreateCareAlert(
    CompanionAnalysisResult result,
    String transcript,
    String turnId,
  ) {
    final controller = careAlertController;
    if (controller == null) return;
    // CR-0052：persist gate 改以 canonical riskLevel 判定，與打字聊天
    // /api/companion/chat 對齊——medium / high / urgent 都建立 Care Alert 紀錄，
    // 讓語音與打字的照護端紀錄一致。canonical 會把 legacy normal→low、
    // attention→medium，避免漏接 legacy 值（裁決 CR-0052 #7）。
    // needsHumanSupport 仍只代表 high/urgent（是否需人為關懷），不再作為 persist gate；
    // Telegram 推播門檻（high/urgent）由後端權威決定，Flutter 不複製此決策。
    final riskLevel =
        CareAlertRiskLevel.fromJson(result.safety.riskLevel).canonical;
    final shouldPersistCareAlert = riskLevel == CareAlertRiskLevel.medium ||
        riskLevel == CareAlertRiskLevel.high ||
        riskLevel == CareAlertRiskLevel.urgent;
    if (!shouldPersistCareAlert) return;
    if (turnId.isEmpty || turnId == _lastAlertedTurnId) return;
    _lastAlertedTurnId = turnId;
    // triggerSummary 來源：優先用後端 companion 產生的 careAlertSummary（白話、非診斷），
    // 缺少時才退回 implicitMeaning（CR-0003 Batch 3 wiring）。
    final careSummary = result.careAlertSummary.trim();
    final summary =
        careSummary.isNotEmpty ? careSummary : result.implicitMeaning.trim();
    // 以 canonical riskLevel 建構，新 alert 不帶 legacy normal/attention（與 CR-0051 同向）。
    final alert = CareAlert(
      id: 'care_alert_$turnId',
      createdAt: DateTime.now(),
      riskLevel: riskLevel,
      category: CareAlertCategory.other,
      triggerSummary: summary.isEmpty ? '對話中偵測到需要關心的狀況' : summary,
      transcriptSnippet: transcript.trim(),
      source: 'companion_analysis',
      isRead: false,
    );
    unawaited(controller.addAlert(alert));
    final notificationService = careAlertNotificationService;
    if (notificationService != null) {
      // fire-and-forget：通知失敗不影響 Realtime，也不影響本機 CareAlert。
      unawaited(notificationService.notify(
        sttProxyUrl: profileController.sttProxyUrl,
        alert: alert,
      ));
    }
  }

  void _applyLocalCompanionFallback(String transcript, String turnId) {
    if (turnId != _latestCompanionTurnId) return;
    final localEmotion = _textEmotionService.analyze(transcript);
    _emotion = _emotionFromEngine(localEmotion.emotion);
    _pendingRealtimeEmotion = _emotion.name;
    _applyEmotionToPet();
  }

  void _applyCompanionPetState(CompanionAnalysisResult result) {
    final expression = result.petExpression.trim();
    final action = result.petAction.trim();
    if (expression.isEmpty || action.isEmpty) return;
    _petMood = result.emotion;
    _petExpression = expression;
    _petAction = action;
    petController.updateEmotionState(
      mood: _petMood,
      expression: _petExpression,
      action: _petAction,
      mode: _petModeFromCompanion(result),
    );
  }

  Map<String, dynamic> _estimateAudioFeatures(String transcript) {
    final startedAt = _speechStartedAt;
    final stoppedAt = _speechStoppedAt ?? DateTime.now();
    final speechDuration = startedAt == null || stoppedAt.isBefore(startedAt)
        ? null
        : stoppedAt.difference(startedAt);
    final silenceDuration = _speechStoppedAt == null
        ? null
        : DateTime.now().difference(_speechStoppedAt!);
    return _voiceFeatureService
        .estimate(
          transcript: transcript,
          speechDuration: speechDuration,
          silenceDuration: silenceDuration,
        )
        .toJson();
  }

  PetMode _petModeFromCompanion(CompanionAnalysisResult result) {
    return switch (result.petExpression) {
      'happy' => PetMode.happy,
      'excited' => PetMode.excited,
      'sad' => PetMode.sad,
      'sleepy' => PetMode.sleepy,
      'concerned' => PetMode.concerned,
      'calm' => PetMode.caring,
      _ => switch (result.emotion) {
          'lonely' || 'sad' || 'anxious' => PetMode.caring,
          'tired' => PetMode.sleepy,
          'happy' => PetMode.happy,
          _ => PetMode.listening,
        },
    };
  }

  UserEmotion _emotionFromEngine(String emotion) {
    return switch (emotion) {
      'lonely' => UserEmotion.lonely,
      'sad' => UserEmotion.sad,
      'anxious' => UserEmotion.anxious,
      'tired' => UserEmotion.tired,
      'happy' => UserEmotion.happy,
      'nostalgic' => UserEmotion.nostalgic,
      _ => UserEmotion.neutral,
    };
  }

  String _companionContextPrompt([CompanionAnalysisResult? result]) {
    final context = result ?? _currentCompanionContext;
    final languageLines = [
      'languageHint=${_currentLanguageRoute.languageHint.value}',
      'replyLanguage=${_currentLanguageRoute.replyLanguage.value}',
      'asrStrategy=${_currentLanguageRoute.strategyName}',
      'asrRouteReason=${_currentLanguageRoute.routeReason}',
      'asrFallback=${_currentLanguageRoute.isFallback}',
    ];
    if (context == null) return languageLines.join('\n');
    return [
      'emotion=${context.emotion}',
      'companionNeed=${context.companionNeed}',
      'replyStrategy=${context.replyStrategy}',
      'petExpression=${context.petExpression}',
      'petAction=${context.petAction}',
      'nextStrategy.mode=${context.nextStrategy.mode}',
      'nextStrategy.instruction=${context.nextStrategy.instruction}',
      ...languageLines,
    ].join('\n');
  }

  void _startTimeout(RealtimeTimeoutType type, {String turnId = ''}) {
    _cancelTimeout(type);
    final duration = timeoutConfig.durationFor(type);
    debugPrint(
      '[VOICE_TIMEOUT] start type=${type.name} duration=${duration.inSeconds}s turn=${turnId.isEmpty ? '-' : turnId}',
    );
    if (type == RealtimeTimeoutType.ttsTimeout) return;
    _timeouts.start(
      type,
      duration,
      () => _handleTimeout(type, turnId: turnId),
    );
  }

  void _cancelTimeout(RealtimeTimeoutType type) {
    _timeouts.cancel(type);
  }

  void _cancelTurnTimeouts() {
    _cancelTimeout(RealtimeTimeoutType.transcriptTimeout);
    _cancelTimeout(RealtimeTimeoutType.responseTimeout);
  }

  void _cancelAllTimeouts() {
    _timeouts.cancelAll();
  }

  void _handleTimeout(RealtimeTimeoutType type, {String turnId = ''}) {
    final plan = timeoutPolicy.planFor(type);
    debugPrint(
      '[VOICE_TIMEOUT] fired type=${type.name} reason=${plan.reason} turn=${turnId.isEmpty ? '-' : turnId}',
    );
    if (turnId.isNotEmpty && !_isActiveTurn(turnId)) {
      debugPrint(
        '[VOICE_TIMEOUT] ignore stale timeout type=${type.name} turn=$turnId active=$_activeTurnId',
      );
      return;
    }
    switch (type) {
      case RealtimeTimeoutType.connectionTimeout:
        unawaited(_recoverToIdleAfterError(
          reason: plan.reason,
          message: plan.fallbackReply,
          stopConnection: plan.stopConnection,
        ));
        break;
      case RealtimeTimeoutType.transcriptTimeout:
        _clearCurrentTurn();
        petController.setModeAndMessage(PetMode.listening, plan.fallbackReply);
        conversationController.showPetBubbleMessage(plan.fallbackReply);
        _transition(plan.targetState, plan.reason);
        break;
      case RealtimeTimeoutType.responseTimeout:
        unawaited(_handleResponseTimeout(plan, turnId));
        break;
      case RealtimeTimeoutType.ttsTimeout:
        petController.setModeAndMessage(PetMode.listening, plan.fallbackReply);
        conversationController.showPetBubbleMessage(plan.fallbackReply);
        _transition(plan.targetState, plan.reason, turnId: turnId);
        break;
      case RealtimeTimeoutType.reconnectTimeout:
        unawaited(_recoverToIdleAfterError(
          reason: plan.reason,
          message: plan.fallbackReply,
          stopConnection: plan.stopConnection,
        ));
        break;
    }
  }

  Future<void> _handleResponseTimeout(
    RealtimeTimeoutRecoveryPlan plan,
    String turnId,
  ) async {
    if (turnId.isNotEmpty && !_isActiveTurn(turnId)) return;
    _cancelTimeout(RealtimeTimeoutType.responseTimeout);
    _lastError = RealtimeFailureType.responseTimeout.message;
    final fallback = plan.fallbackReply;
    if (_pendingRealtimeUserText.isNotEmpty) {
      await conversationController.handleRealtimeAssistantReply(
        fallback,
        turnId: turnId,
      );
    } else {
      petController.setModeAndMessage(PetMode.listening, fallback);
      conversationController.showPetBubbleMessage(fallback);
    }
    _clearCurrentTurn();
    // Turn-based：寵物這一輪沒有及時回覆 → 顯示白話 fallback 後回到 idle，
    // 不自動回 listening，由使用者決定要不要再按一次重講。
    _finishPetTurn(plan.reason);
  }

  void _clearCurrentTurn() {
    _activeTurnId = '';
    _responseTurnId = '';
    _pendingRealtimeTurnId = '';
    _pendingRealtimeUserText = '';
    _partialTranscript = '';
    _latestCompanionTurnId = '';
    _lastAlertedTurnId = '';
    _turnCoordinator.reset();
    _cancelTurnTimeouts();
    conversationController.clearRealtimeTranscriptState();
  }

  /// Turn-based：寵物這一輪（思考 + 說話）結束的收尾。
  ///
  /// 暫停麥克風、清掉這一輪的 turn 狀態、回到 **idle**（不是 listening），保留同一條
  /// Realtime 連線。使用者要說下一句，必須再次按語音按鈕（走 [startRealtimeConversation]
  /// 的「下一句」分支）。對 `assistantAudioEnd` 與 `assistantResponseDone` 都呼叫，
  /// 具冪等性：已在 idle 就不重複處理（避免兩個事件先後到達時互相覆蓋）。
  /// CR-0089：response.done 到達時呼叫。本輪有語音 → 不立即收 turn，保留 talk /
  /// 字幕並暫停麥克風（避免播放時被使用者插話蓋字幕），等 [_audioStopFallback] 或
  /// assistantAudioPlaybackStopped 才真的收；純文字回覆（無語音）則照舊立即收。
  /// assistantResponseDone 與 assistantAudioEnd 都會走這裡，靠 _awaitingAudioStop
  /// 與 _finishPetTurn 的 idle guard 達成幂等。
  void _requestFinishPetTurn(String reason) {
    if (_awaitingAudioStop) return; // 已在等播完（第二次 done/audioEnd 忽略）。
    if (_currentTurnHadAudio && _state != VoiceAgentState.idle) {
      _awaitingAudioStop = true;
      // 沿用既有行為：response.done 即暫停麥克風，語音尾段不被使用者插話覆蓋字幕。
      realtimeVoiceService.pauseMicInput();
      _startAudioStopFallback(reason);
      return;
    }
    _finishPetTurn(reason);
  }

  void _startAudioStopFallback(String reason) {
    _audioStopFallbackTimer?.cancel();
    _audioStopFallbackTimer = Timer(_audioStopFallback, () {
      // 漏掉 output_audio_buffer.stopped 時的防呆上限：把 turn 收掉，避免永遠卡 speaking。
      _awaitingAudioStop = false;
      _finishPetTurn('${reason}_audio_stop_fallback');
    });
  }

  void _finishPetTurn(String reason) {
    if (_state == VoiceAgentState.idle) return;
    _audioStopFallbackTimer?.cancel();
    _audioStopFallbackTimer = null;
    _awaitingAudioStop = false;
    _currentTurnHadAudio = false;
    _cancelTimeout(RealtimeTimeoutType.responseTimeout);
    _turnCoordinator.clearActiveTurn(_responseTurnId);
    _activeTurnId = '';
    _responseTurnId = '';
    _partialTranscript = '';
    // 這一輪結束 → 重置背景捕捉去重，下一輪即使說同一句也能正常記錄。
    _lastBackgroundUserTranscript = '';
    realtimeVoiceService.pauseMicInput();
    _transition(VoiceAgentState.idle, reason);
  }

  bool _isActiveTurn(String turnId) {
    return turnId.isEmpty || turnId == _activeTurnId;
  }

  void _transition(
    VoiceAgentState newState,
    String reason, {
    String turnId = '',
    bool notify = true,
  }) {
    if (turnId.isNotEmpty && !_isActiveTurn(turnId)) {
      debugPrint(
        '[VOICE_STATE] drop stale transition reason=$reason turn=$turnId active=$_activeTurnId',
      );
      return;
    }
    final previous = _state;
    _state = newState;
    debugPrint(
      '[VOICE_STATE] ${previous.name} -> ${newState.name} reason=$reason turn=${turnId.isEmpty ? '-' : turnId}',
    );
    switch (newState) {
      case VoiceAgentState.listening:
        _petExpression = 'listening';
        _petAction = 'listen';
        petController.setMode(PetMode.listening);
        // Turn-based：開始聽使用者這一句 → 開啟麥克風。
        realtimeVoiceService.resumeMicInput();
        break;
      case VoiceAgentState.thinking:
        _petExpression = 'thinking';
        _petAction = 'idle';
        petController.setMode(PetMode.thinking);
        // Turn-based：寵物開始回覆 → 關閉麥克風，避免雜音被當成新一輪。
        realtimeVoiceService.pauseMicInput();
        break;
      case VoiceAgentState.transcribing:
        _petExpression = 'listening';
        _petAction = 'listen';
        petController.setMode(PetMode.listening);
        realtimeVoiceService.resumeMicInput();
        break;
      case VoiceAgentState.speaking:
        _petExpression = 'speaking';
        _petAction = 'speak';
        petController.setMode(PetMode.talking, isSpeaking: true);
        // Turn-based：寵物說話中 → 維持麥克風關閉，咳嗽 / 背景音都不打斷。
        realtimeVoiceService.pauseMicInput();
        break;
      case VoiceAgentState.recovering:
        petController.setMode(PetMode.thinking);
        realtimeVoiceService.pauseMicInput();
        break;
      case VoiceAgentState.error:
        petController.setMode(PetMode.sad);
        realtimeVoiceService.pauseMicInput();
        break;
      case VoiceAgentState.idle:
        // Turn-based：回到 idle（不論是寵物說完，或手動停止）→ 關閉麥克風待命，
        // 等使用者再次按鈕才開始下一句。
        realtimeVoiceService.pauseMicInput();
        break;
      case VoiceAgentState.connecting:
      case VoiceAgentState.ready:
        // Keep current pet state during transition.
        break;
    }
    if (notify) {
      notifyListeners();
    }
  }

  void _applyEmotionToPet() {
    switch (_emotion) {
      case UserEmotion.lonely:
        _petMood = 'caring';
        _petExpression = 'concerned';
        _petAction = 'comfort';
        petController.updateEmotionState(
          mood: _petMood,
          expression: _petExpression,
          action: _petAction,
          mode: PetMode.concerned,
        );
        break;
      case UserEmotion.sad:
        _petMood = 'caring';
        _petExpression = 'concerned';
        _petAction = 'comfort';
        petController.updateEmotionState(
          mood: _petMood,
          expression: _petExpression,
          action: _petAction,
          mode: PetMode.concerned,
        );
        break;
      case UserEmotion.anxious:
        _petMood = 'worried';
        _petExpression = 'concerned';
        _petAction = 'comfort';
        petController.updateEmotionState(
          mood: _petMood,
          expression: _petExpression,
          action: _petAction,
          mode: PetMode.concerned,
        );
        break;
      case UserEmotion.happy:
        _petMood = 'happy';
        _petExpression = 'smile';
        _petAction = 'cheer';
        petController.updateEmotionState(
          mood: _petMood,
          expression: _petExpression,
          action: _petAction,
          mode: PetMode.smile,
        );
        break;
      case UserEmotion.tired:
        _petMood = 'caring';
        _petExpression = 'concerned';
        _petAction = 'listen';
        petController.updateEmotionState(
          mood: _petMood,
          expression: _petExpression,
          action: _petAction,
          mode: PetMode.caring,
        );
        break;
      case UserEmotion.angry:
        _petMood = 'caring';
        _petExpression = 'concerned';
        _petAction = 'comfort';
        petController.updateEmotionState(
          mood: _petMood,
          expression: _petExpression,
          action: _petAction,
          mode: PetMode.caring,
        );
        break;
      case UserEmotion.nostalgic:
        _petMood = 'nostalgic';
        _petExpression = 'calm';
        _petAction = 'nod';
        petController.updateEmotionState(
          mood: _petMood,
          expression: _petExpression,
          action: _petAction,
          mode: PetMode.caring,
        );
        break;
      case UserEmotion.neutral:
        _petMood = 'neutral';
        _petExpression = 'listening';
        _petAction = 'listen';
        petController.updateEmotionState(
          mood: _petMood,
          expression: _petExpression,
          action: _petAction,
          mode: PetMode.listening,
        );
        break;
    }
    debugPrint(
      '[PET_STATE_FROM_EMOTION] mood=$_petMood expression=$_petExpression action=$_petAction',
    );
    notifyListeners();
  }

  UserEmotion detectEmotion(String text) {
    if (text.contains('孤單') ||
        text.contains('寂寞') ||
        text.contains('無聊') ||
        text.contains('沒人陪') ||
        text.contains('一個人') ||
        text.contains('沒有人陪') ||
        text.contains('足安靜') ||
        text.contains('厝內')) {
      return UserEmotion.lonely;
    }
    if (text.contains('難過') ||
        text.contains('想哭') ||
        text.contains('累') ||
        text.contains('足累') ||
        text.contains('心情不好')) {
      return UserEmotion.sad;
    }
    if (text.contains('擔心') || text.contains('害怕') || text.contains('緊張')) {
      return UserEmotion.anxious;
    }
    if (text.contains('累') ||
        text.contains('沒力') ||
        text.contains('疲倦') ||
        text.contains('袂好睏')) {
      return UserEmotion.tired;
    }
    if (text.contains('生氣') || text.contains('火大') || text.contains('不爽')) {
      return UserEmotion.angry;
    }
    if (text.contains('以前') || text.contains('懷念') || text.contains('從前')) {
      return UserEmotion.nostalgic;
    }
    if (text.contains('開心') || text.contains('很好') || text.contains('快樂')) {
      return UserEmotion.happy;
    }
    return UserEmotion.neutral;
  }

  _RenameResult _tryHandleRenameIntent(String text) {
    final normalized = text.trim();
    final renameOnlyIntent =
        RegExp(r'(改名字|改名)', caseSensitive: false).hasMatch(normalized);
    final withName = RegExp(
      r'(?:你叫|你以後叫|我想幫你改名字叫|我要幫你改名字叫|你的名字改成|我想把你改名叫)([\u4e00-\u9fa5A-Za-z0-9]{1,12})',
    ).firstMatch(normalized);
    if (withName != null) {
      final newName = withName.group(1)?.trim();
      if (newName != null && newName.isNotEmpty) {
        unawaited(profileController.renamePet(newName, source: 'conversation'));
        return _RenameResult(
          handled: true,
          reply: '好呀，以後我就叫$newName。',
        );
      }
    }
    final directShort =
        RegExp(r'^你叫([\u4e00-\u9fa5A-Za-z0-9]{1,12})$').firstMatch(normalized);
    if (directShort != null) {
      final newName = directShort.group(1)!;
      unawaited(profileController.renamePet(newName, source: 'conversation'));
      return _RenameResult(handled: true, reply: '好呀，以後我就叫$newName。');
    }

    if (renameOnlyIntent) {
      return const _RenameResult(
        handled: true,
        reply: '好呀，你想幫我取什麼名字呢？',
      );
    }
    return const _RenameResult(handled: false);
  }

  Future<void> _handleRealtimeFailure(Object error) async {
    if (_isHandlingRealtimeFailure ||
        _state == VoiceAgentState.error ||
        _state == VoiceAgentState.idle) {
      return;
    }
    _isHandlingRealtimeFailure = true;
    try {
      debugPrint('[VoiceAgentController] realtime unavailable: $error');
      final failureType = error is RealtimeFailure
          ? error.type
          : realtimeVoiceService.lastFailureType;
      _lastError = failureType == RealtimeFailureType.none
          ? error.toString()
          : failureType.message;
      await _recoverToErrorAfterFailure(
        reason: failureType == RealtimeFailureType.none
            ? 'connection_failed'
            : failureType.name,
        message: _lastError.isEmpty ? '連線失敗，點我重試' : _lastError,
        stopConnection: true,
      );
    } finally {
      _isHandlingRealtimeFailure = false;
    }
  }

  void _handleRealtimeRecoverableFailure(String reason) {
    if (!_userRequestedRealtime) {
      debugPrint(
        '[VoiceAgentController] ignore recoverable failure without user request reason=$reason',
      );
      return;
    }
    if (_state == VoiceAgentState.connecting ||
        _state == VoiceAgentState.recovering) {
      debugPrint(
        '[VoiceAgentController] realtime recovery already running reason=$reason',
      );
      return;
    }
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      unawaited(_recoverToErrorAfterFailure(
        reason: '${reason}_max_reconnect_reached',
        message: '語音連線中斷，請點重新連線。',
        stopConnection: true,
      ));
      return;
    }
    _reconnectAttempts += 1;
    debugPrint('[VoiceAgentController] realtime recovering reason=$reason');
    _lastError = '';
    _transition(VoiceAgentState.recovering, reason);
    unawaited(_recoverAndReconnect(
      reason: reason,
      message: '語音連線重新建立中',
    ));
  }

  Future<void> _recoverAndReconnect({
    required String reason,
    required String message,
  }) async {
    if (!_userRequestedRealtime) return;
    _connectionAttemptId += 1;
    _isConnecting = true;
    _cancelAllTimeouts();
    _clearCurrentTurn();
    await realtimeVoiceService.stop();
    petController.setModeAndMessage(PetMode.listening, message);
    conversationController.showPetBubbleMessage(message);
    final attemptId = ++_connectionAttemptId;
    _transition(VoiceAgentState.connecting, '${reason}_reconnect_started');
    _startTimeout(RealtimeTimeoutType.reconnectTimeout);
    try {
      final health = await realtimeVoiceService.checkBackendHealth(
        AppConfig.healthUrlForSttProxy(profileController.sttProxyUrl),
      );
      if (!health.ok || !health.hasOpenAiKey) {
        final type = !health.ok
            ? RealtimeFailureType.backendUnavailable
            : RealtimeFailureType.missingApiKey;
        throw RealtimeFailure(type, type.message);
      }
      await realtimeVoiceService.connect(
        realtimeCallUrl:
            AppConfig.realtimeCallUrlForSttProxy(profileController.sttProxyUrl),
        petName: profileController.petName,
        userId: memoryController.userId,
        companionContext: _companionContextPrompt(),
        languageHint: _currentLanguageRoute.languageHint.value,
        replyLanguage: _currentLanguageRoute.replyLanguage.value,
      );
      if (attemptId != _connectionAttemptId) {
        debugPrint(
          '[VoiceAgentController] ignore stale reconnect completion attempt=$attemptId active=$_connectionAttemptId',
        );
        return;
      }
      await realtimeVoiceService.startListening();
      _cancelTimeout(RealtimeTimeoutType.reconnectTimeout);
    } catch (error) {
      debugPrint('[VoiceAgentController] reconnect failed: $error');
      final failureType = error is RealtimeFailure
          ? error.type
          : realtimeVoiceService.lastFailureType;
      await _recoverToErrorAfterFailure(
        reason: failureType == RealtimeFailureType.none
            ? 'reconnect_failed'
            : failureType.name,
        message: failureType == RealtimeFailureType.none
            ? '連線失敗，點我重試'
            : failureType.message,
        stopConnection: true,
      );
    } finally {
      _isConnecting = false;
    }
  }

  Future<void> _recoverToIdleAfterError({
    required String reason,
    String? message,
    bool stopConnection = false,
  }) async {
    _connectionAttemptId += 1;
    _isConnecting = false;
    _cancelAllTimeouts();
    _clearCurrentTurn();
    if (stopConnection) {
      await realtimeVoiceService.stop();
    }
    _transition(VoiceAgentState.idle, reason);
    if (message != null && message.isNotEmpty) {
      petController.setModeAndMessage(PetMode.listening, message);
      conversationController.showPetBubbleMessage(message);
    }
  }

  Future<void> _recoverToErrorAfterFailure({
    required String reason,
    String? message,
    bool stopConnection = false,
  }) async {
    _connectionAttemptId += 1;
    _isConnecting = false;
    _cancelAllTimeouts();
    _clearCurrentTurn();
    if (stopConnection) {
      await realtimeVoiceService.stop();
    }
    _transition(VoiceAgentState.error, reason);
    if (message != null && message.isNotEmpty) {
      petController.setModeAndMessage(PetMode.sad, message);
      conversationController.showPetBubbleMessage(message);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        if (_state == VoiceAgentState.ready ||
            _state == VoiceAgentState.listening ||
            _state == VoiceAgentState.transcribing ||
            _state == VoiceAgentState.thinking ||
            _state == VoiceAgentState.speaking) {
          unawaited(stopRealtimeConversation());
        }
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelAllTimeouts();
    _timeouts.dispose();
    _audioStopFallbackTimer?.cancel();
    _sub?.cancel();
    realtimeVoiceService.dispose();
    super.dispose();
  }
}

class _RenameResult {
  const _RenameResult({
    required this.handled,
    this.reply,
  });

  final bool handled;
  final String? reply;
}
