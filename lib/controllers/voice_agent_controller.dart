import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/companion_analysis_result.dart';
import '../models/conversation_turn.dart';
import '../models/pet_status.dart';
import '../models/realtime_timeout.dart';
import '../models/voice_agent_state.dart';
import '../services/ai_navigation_service.dart';
import '../services/companion_engine_service.dart';
import '../services/emotion_services.dart';
import '../services/realtime_timeout_registry.dart';
import '../services/realtime_turn_coordinator.dart';
import '../services/realtime_voice_service.dart';
import 'app_navigation_controller.dart';
import 'conversation_controller.dart';
import 'memory_controller.dart';
import 'pet_controller.dart';
import 'pet_stats_controller.dart';
import 'profile_controller.dart';

class VoiceAgentController extends ChangeNotifier {
  VoiceAgentController({
    required this.profileController,
    required this.petController,
    required this.petStatsController,
    required this.conversationController,
    required this.realtimeVoiceService,
    required this.companionEngineService,
    required this.memoryController,
    required this.navigationService,
    required this.navigationController,
    this.timeoutConfig = const RealtimeTimeoutConfig(),
    this.timeoutPolicy = const RealtimeTimeoutPolicy(),
  });

  final ProfileController profileController;
  final PetController petController;
  final PetStatsController petStatsController;
  final ConversationController conversationController;
  final RealtimeVoiceService realtimeVoiceService;
  final CompanionEngineService companionEngineService;
  final MemoryController memoryController;
  final AiNavigationService navigationService;
  final AppNavigationController navigationController;
  final RealtimeTimeoutConfig timeoutConfig;
  final RealtimeTimeoutPolicy timeoutPolicy;
  final TextEmotionService _textEmotionService = const TextEmotionService();

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
  CompanionAnalysisResult? _currentCompanionContext;
  bool _skipNextAssistantText = false;
  int _connectionAttemptId = 0;
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
  String get activeTurnId => _activeTurnId;
  String get partialTranscript => _partialTranscript;
  bool get isRealtimeReady =>
      _state != VoiceAgentState.idle &&
      _state != VoiceAgentState.error &&
      _state != VoiceAgentState.recovering;

  Future<void> startRealtimeConversation() async {
    if (_state == VoiceAgentState.connecting ||
        _state == VoiceAgentState.ready ||
        _state == VoiceAgentState.listening ||
        _state == VoiceAgentState.thinking ||
        _state == VoiceAgentState.speaking) {
      return;
    }
    final attemptId = ++_connectionAttemptId;
    _transition(VoiceAgentState.connecting, 'connect_started');
    _startTimeout(RealtimeTimeoutType.connectionTimeout);
    _lastError = '';
    petController.setMessage('我在聽，慢慢說。');
    notifyListeners();
    _sub?.cancel();
    _sub = realtimeVoiceService.events.listen(_handleRealtimeEvent);
    try {
      debugPrint('[PET_NAME] current=${profileController.petName}');
      await realtimeVoiceService.connect(
        realtimeCallUrl:
            AppConfig.realtimeCallUrlForSttProxy(profileController.sttProxyUrl),
        petName: profileController.petName,
        userId: memoryController.userId,
        companionContext: _companionContextPrompt(),
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
      _handleRealtimeFailureSilently(error);
    }
  }

  Future<void> stopRealtimeConversation() async {
    _cancelAllTimeouts();
    await realtimeVoiceService.stop();
    _lastError = '';
    _activeTurnId = '';
    _responseTurnId = '';
    _partialTranscript = '';
    _turnCoordinator.reset();
    _transition(VoiceAgentState.idle, 'manual_stop');
    petController.setMessage('我先在旁邊陪你。想不到要聊什麼也沒關係，要不要跟我說說今天最舒服的一刻？');
  }

  void _handleRealtimeEvent(RealtimeVoiceEvent event) {
    switch (event.type) {
      case RealtimeEventType.state:
        _applyStateFromPayload(event.payload);
        break;
      case RealtimeEventType.userSpeechStarted:
        _startTimeout(RealtimeTimeoutType.transcriptTimeout);
        break;
      case RealtimeEventType.userSpeechStopped:
        _startTimeout(RealtimeTimeoutType.transcriptTimeout);
        break;
      case RealtimeEventType.partialTranscript:
        _partialTranscript = event.payload.trim();
        if (_partialTranscript.isNotEmpty) {
          _transition(
            VoiceAgentState.transcribing,
            'partial_transcript_received',
            notify: false,
          );
          notifyListeners();
        }
        break;
      case RealtimeEventType.finalTranscript:
        _cancelTimeout(RealtimeTimeoutType.transcriptTimeout);
        final decision = _turnCoordinator.acceptFinalTranscript(event.payload);
        if (!decision.accepted) {
          debugPrint(
            '[VoiceAgentController] ignore transcript reason=${decision.reason}',
          );
          return;
        }
        final transcript = decision.transcript;
        final turnId = decision.turnId;
        _cancelTurnTimeouts();
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
          petController.setMessage(navigationIntent.reply);
          conversationController.appendExternalTurn(
            ConversationTurn(
              timestamp: DateTime.now(),
              userText: transcript,
              petReply: navigationIntent.reply,
              toolName: 'navigation',
              turnId: turnId,
              emotionTag: UserEmotion.neutral.name,
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
        _transition(VoiceAgentState.ready, 'data_channel_open');
        break;
      case RealtimeEventType.dataChannelClosed:
        _handleRealtimeRecoverableFailure('data_channel_closed');
        break;
      case RealtimeEventType.peerConnectionFailed:
        _handleRealtimeRecoverableFailure('peer_connection_failed');
        break;
      case RealtimeEventType.error:
        _handleRealtimeFailureSilently(event.payload);
        break;
    }
  }

  void _applyStateFromPayload(String value) {
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
    if (context == null) return '';
    return [
      'emotion=${context.emotion}',
      'companionNeed=${context.companionNeed}',
      'replyStrategy=${context.replyStrategy}',
      'petExpression=${context.petExpression}',
      'petAction=${context.petAction}',
      'nextStrategy.mode=${context.nextStrategy.mode}',
      'nextStrategy.instruction=${context.nextStrategy.instruction}',
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
        _transition(plan.targetState, plan.reason);
        break;
      case RealtimeTimeoutType.responseTimeout:
        unawaited(_handleResponseTimeout(plan, turnId));
        break;
      case RealtimeTimeoutType.ttsTimeout:
        petController.setModeAndMessage(PetMode.listening, plan.fallbackReply);
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
    final fallback = plan.fallbackReply;
    if (_pendingRealtimeUserText.isNotEmpty) {
      await conversationController.handleRealtimeAssistantReply(
        fallback,
        turnId: turnId,
      );
    } else {
      petController.setModeAndMessage(PetMode.listening, fallback);
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
        text.contains('沒有人陪')) {
      return UserEmotion.lonely;
    }
    if (text.contains('難過') ||
        text.contains('想哭') ||
        text.contains('累') ||
        text.contains('心情不好')) {
      return UserEmotion.sad;
    }
    if (text.contains('擔心') || text.contains('害怕') || text.contains('緊張')) {
      return UserEmotion.anxious;
    }
    if (text.contains('累') || text.contains('沒力') || text.contains('疲倦')) {
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

  void _handleRealtimeFailureSilently(Object error) {
    debugPrint('[VoiceAgentController] realtime unavailable: $error');
    _lastError = '';
    _transition(VoiceAgentState.recovering, 'connection_failed');
    unawaited(_recoverToIdleAfterError(
      reason: 'connection_failed',
      message: '目前連不到即時語音服務。你還是可以先用文字跟我聊天，或確認手機和電腦在同一個 Wi-Fi。',
      stopConnection: true,
    ));
  }

  void _handleRealtimeRecoverableFailure(String reason) {
    debugPrint('[VoiceAgentController] realtime recovering reason=$reason');
    _lastError = '';
    _transition(VoiceAgentState.recovering, reason);
    unawaited(_recoverAndReconnect(
      reason: reason,
      message: '剛剛連線有點不穩，我們再試一次。',
    ));
  }

  Future<void> _recoverAndReconnect({
    required String reason,
    required String message,
  }) async {
    _connectionAttemptId += 1;
    _cancelAllTimeouts();
    _clearCurrentTurn();
    await realtimeVoiceService.stop();
    petController.setModeAndMessage(PetMode.listening, message);
    final attemptId = ++_connectionAttemptId;
    _transition(VoiceAgentState.connecting, '${reason}_reconnect_started');
    _startTimeout(RealtimeTimeoutType.reconnectTimeout);
    try {
      await realtimeVoiceService.connect(
        realtimeCallUrl:
            AppConfig.realtimeCallUrlForSttProxy(profileController.sttProxyUrl),
        petName: profileController.petName,
        userId: memoryController.userId,
        companionContext: _companionContextPrompt(),
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
      await _recoverToIdleAfterError(
        reason: 'reconnect_failed',
        message: message,
        stopConnection: true,
      );
    }
  }

  Future<void> _recoverToIdleAfterError({
    required String reason,
    String? message,
    bool stopConnection = false,
  }) async {
    _connectionAttemptId += 1;
    _cancelAllTimeouts();
    _clearCurrentTurn();
    if (stopConnection) {
      await realtimeVoiceService.stop();
    }
    _transition(VoiceAgentState.idle, reason);
    if (message != null && message.isNotEmpty) {
      petController.setModeAndMessage(PetMode.listening, message);
    }
  }

  @override
  void dispose() {
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
