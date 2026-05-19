import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/companion_analysis_result.dart';
import '../models/conversation_turn.dart';
import '../models/language_route.dart';
import '../models/pet_status.dart';
import '../models/realtime_timeout.dart';
import '../models/voice_agent_state.dart';
import '../services/ai_navigation_service.dart';
import '../services/companion_engine_service.dart';
import '../services/emotion_services.dart';
import '../services/language_routing_service.dart';
import '../services/realtime_timeout_registry.dart';
import '../services/realtime_turn_coordinator.dart';
import '../services/realtime_voice_service.dart';
import 'app_navigation_controller.dart';
import 'agent_tool_controller.dart';
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
    this.agentToolController,
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
  final AgentToolController? agentToolController;
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
  String _activeTurnId = '';
  String _responseTurnId = '';
  String _latestCompanionTurnId = '';
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
    if (_isConnecting || realtimeVoiceService.isConnecting) {
      return;
    }
    if (_state == VoiceAgentState.ready ||
        _state == VoiceAgentState.listening ||
        _state == VoiceAgentState.thinking ||
        _state == VoiceAgentState.speaking) {
      if (!realtimeVoiceService.isConnectionUsable) {
        _handleRealtimeRecoverableFailure('active_connection_unusable');
      }
      return;
    }
    final attemptId = ++_connectionAttemptId;
    _isConnecting = true;
    _reconnectAttempts = 0;
    _lastError = '';
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

  void _handleRealtimeEvent(RealtimeVoiceEvent event) {
    switch (event.type) {
      case RealtimeEventType.state:
        _applyStateFromPayload(event.payload);
        break;
      case RealtimeEventType.userSpeechStarted:
        _speechStartedAt = DateTime.now();
        _speechStoppedAt = null;
        _partialTranscript = '';
        conversationController.beginRealtimeUserSpeech();
        conversationController.showPetBubbleMessage('我在聽，慢慢說。');
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
        _transition(
          VoiceAgentState.listening,
          'realtime_response_done',
          turnId: _responseTurnId,
        );
        _turnCoordinator.clearActiveTurn(_responseTurnId);
        _activeTurnId = '';
        _responseTurnId = '';
        break;
      case RealtimeEventType.assistantText:
        if (_skipNextAssistantText) {
          _skipNextAssistantText = false;
          return;
        }
        final responseTurnId =
            _responseTurnId.isEmpty ? _pendingRealtimeTurnId : _responseTurnId;
        if (responseTurnId.isNotEmpty && !_isActiveTurn(responseTurnId)) {
          debugPrint(
            '[VoiceAgentController] drop stale assistant text turn=$responseTurnId active=$_activeTurnId',
          );
          return;
        }
        unawaited(petStatsController.markRealtimeConversationCompleted());
        conversationController.handleRealtimeAssistantReply(
          event.payload,
          turnId: responseTurnId,
        );
        if (_pendingRealtimeUserText.isNotEmpty &&
            _pendingRealtimeTurnId.isNotEmpty) {
          unawaited(
            memoryController.extractMemory(
              sessionId: conversationController.activeSessionId,
              turnId: _pendingRealtimeTurnId,
              userText: _pendingRealtimeUserText,
              aiReply: event.payload.trim(),
              emotion: _pendingRealtimeEmotion,
            ),
          );
        }
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
      case RealtimeEventType.assistantAudioEnd:
        _cancelTimeout(RealtimeTimeoutType.responseTimeout);
        _transition(
          VoiceAgentState.listening,
          'speaking_completed',
          turnId: _responseTurnId,
        );
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
    if (mapped == VoiceAgentState.ready ||
        mapped == VoiceAgentState.listening) {
      _cancelTimeout(RealtimeTimeoutType.connectionTimeout);
      _cancelTimeout(RealtimeTimeoutType.reconnectTimeout);
    }
    _transition(mapped, 'service_state_$value');
  }

  Future<void> _handleFinalTranscript(String realtimeTranscript) async {
    final normalizedRealtimeTranscript = realtimeTranscript.trim();
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
    unawaited(
      agentToolController?.routeFromUserText(
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
      ),
    );
    unawaited(_analyzeCompanionTranscript(transcript, turnId));

    final navigationIntent = navigationService.detect(transcript);
    if (navigationIntent != null) {
      if (!_isActiveTurn(turnId)) return;
      navigationController.navigateTo(navigationIntent.route);
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
    if (conversationController.shouldHandleAsLocalCommand(transcript)) {
      _pendingRealtimeUserText = '';
      _skipNextAssistantText = true;
      unawaited(_handleLocalRealtimeCommand(transcript, turnId));
      return;
    }
    final renameResult = _tryHandleRenameIntent(transcript);
    _emotion = detectEmotion(transcript);
    debugPrint('[EMOTION] text=$transcript emotion=${_emotion.name}');
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

  Future<void> _handleLocalRealtimeCommand(String text, String turnId) async {
    if (!_isActiveTurn(turnId)) return;
    _transition(VoiceAgentState.thinking, 'local_command_started',
        turnId: turnId);
    try {
      await conversationController.quickAction(text);
    } catch (error) {
      await conversationController.showFallbackMessage(
        '我剛剛查詢時卡住了，可以再說一次嗎？',
      );
    } finally {
      if (_state != VoiceAgentState.error && _state != VoiceAgentState.idle) {
        _transition(
          VoiceAgentState.listening,
          'local_command_completed',
          turnId: turnId,
        );
      }
    }
  }

  Future<void> _analyzeCompanionTranscript(
    String transcript,
    String turnId,
  ) async {
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
      _emotion = _emotionFromEngine(result.emotion);
      _pendingRealtimeEmotion = result.emotion;
      _applyCompanionPetState(result);
      unawaited(realtimeVoiceService.updateCompanionContext(
        _companionContextPrompt(result),
      ));
      debugPrint(
        '[COMPANION_ENGINE] turn=$turnId emotion=${result.emotion} need=${result.companionNeed} strategy=${result.replyStrategy}',
      );
      notifyListeners();
    } catch (error) {
      debugPrint('[COMPANION_ENGINE] fallback: $error');
      _applyLocalCompanionFallback(transcript, turnId);
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
    _transition(plan.targetState, plan.reason);
  }

  void _clearCurrentTurn() {
    _activeTurnId = '';
    _responseTurnId = '';
    _pendingRealtimeTurnId = '';
    _pendingRealtimeUserText = '';
    _partialTranscript = '';
    _latestCompanionTurnId = '';
    _turnCoordinator.reset();
    _cancelTurnTimeouts();
    conversationController.clearRealtimeTranscriptState();
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
        break;
      case VoiceAgentState.thinking:
        _petExpression = 'thinking';
        _petAction = 'idle';
        petController.setMode(PetMode.thinking);
        break;
      case VoiceAgentState.transcribing:
        _petExpression = 'listening';
        _petAction = 'listen';
        petController.setMode(PetMode.listening);
        break;
      case VoiceAgentState.speaking:
        _petExpression = 'speaking';
        _petAction = 'speak';
        petController.setMode(PetMode.talking, isSpeaking: true);
        break;
      case VoiceAgentState.recovering:
        petController.setMode(PetMode.thinking);
        break;
      case VoiceAgentState.error:
        petController.setMode(PetMode.sad);
        break;
      case VoiceAgentState.idle:
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
