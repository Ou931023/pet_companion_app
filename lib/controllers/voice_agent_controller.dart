import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/companion_analysis_result.dart';
import '../models/conversation_turn.dart';
import '../models/pet_status.dart';
import '../models/voice_agent_state.dart';
import '../services/ai_navigation_service.dart';
import '../services/companion_engine_service.dart';
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
  String _latestCompanionTurnId = '';
  String _lastAnalyzedTranscript = '';
  CompanionAnalysisResult? _currentCompanionContext;
  bool _skipNextAssistantText = false;

  VoiceAgentState get state => _state;
  UserEmotion get emotion => _emotion;
  String get petMood => _petMood;
  String get petExpression => _petExpression;
  String get petAction => _petAction;
  String get lastError => _lastError;
  CompanionAnalysisResult? get currentCompanionContext =>
      _currentCompanionContext;
  bool get isRealtimeReady =>
      _state != VoiceAgentState.idle && _state != VoiceAgentState.error;

  Future<void> startRealtimeConversation() async {
    if (_state == VoiceAgentState.connecting ||
        _state == VoiceAgentState.connected) {
      return;
    }
    _setState(VoiceAgentState.connecting);
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
      await realtimeVoiceService.startListening();
    } catch (error) {
      _handleRealtimeFailureSilently(error);
    }
  }

  Future<void> stopRealtimeConversation() async {
    await realtimeVoiceService.stop();
    _lastError = '';
    _setState(VoiceAgentState.idle);
    petController.setMessage('我先在旁邊陪你。想不到要聊什麼也沒關係，要不要跟我說說今天最舒服的一刻？');
  }

  void _handleRealtimeEvent(RealtimeVoiceEvent event) {
    switch (event.type) {
      case RealtimeEventType.state:
        _applyStateFromPayload(event.payload);
        break;
      case RealtimeEventType.userTranscript:
        final transcript = event.payload.trim();
        if (transcript.isEmpty) return;
        final turnId = 'rt_${DateTime.now().microsecondsSinceEpoch}';
        if (transcript != _lastAnalyzedTranscript) {
          _lastAnalyzedTranscript = transcript;
          _latestCompanionTurnId = turnId;
          unawaited(_analyzeCompanionTranscript(transcript, turnId));
        }

        final navigationIntent = navigationService.detect(transcript);
        if (navigationIntent != null) {
          navigationController.navigateTo(navigationIntent.route);
          petController.setMessage(navigationIntent.reply);
          conversationController.appendExternalTurn(
            ConversationTurn(
              timestamp: DateTime.now(),
              userText: transcript,
              petReply: navigationIntent.reply,
              toolName: 'navigation',
              emotionTag: UserEmotion.neutral.name,
            ),
          );
          _pendingRealtimeUserText = '';
          _pendingRealtimeTurnId = '';
          _skipNextAssistantText = true;
          notifyListeners();
          return;
        }
        if (conversationController.shouldHandleAsLocalCommand(transcript)) {
          _pendingRealtimeUserText = '';
          _pendingRealtimeTurnId = '';
          _skipNextAssistantText = true;
          unawaited(_handleLocalRealtimeCommand(transcript));
          return;
        }
        final renameResult = _tryHandleRenameIntent(transcript);
        _emotion = detectEmotion(transcript);
        debugPrint('[EMOTION] text=$transcript emotion=${_emotion.name}');
        _pendingRealtimeUserText = transcript;
        _pendingRealtimeEmotion = _emotion.name;
        _pendingRealtimeTurnId = turnId;
        _applyEmotionToPet();
        conversationController.appendExternalTurn(
          ConversationTurn(
            timestamp: DateTime.now(),
            userText: transcript,
            petReply: renameResult.reply ?? '',
            toolName: renameResult.handled ? 'renamePet' : 'realtime-user',
            emotionTag: _emotion.name,
          ),
        );
        if (renameResult.reply != null) {
          unawaited(conversationController
              .handleRealtimeAssistantReply(renameResult.reply!));
        }
        break;
      case RealtimeEventType.assistantText:
        if (_skipNextAssistantText) {
          _skipNextAssistantText = false;
          return;
        }
        unawaited(petStatsController.markRealtimeConversationCompleted());
        conversationController.handleRealtimeAssistantReply(event.payload);
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
        _setState(VoiceAgentState.speaking);
        break;
      case RealtimeEventType.assistantAudioEnd:
        _setState(VoiceAgentState.listening);
        break;
      case RealtimeEventType.error:
        _handleRealtimeFailureSilently(event.payload);
        break;
    }
  }

  void _applyStateFromPayload(String value) {
    final mapped = switch (value) {
      'connecting' => VoiceAgentState.connecting,
      'connected' => VoiceAgentState.connected,
      'listening' => VoiceAgentState.listening,
      'thinking' => VoiceAgentState.thinking,
      'speaking' => VoiceAgentState.speaking,
      _ => VoiceAgentState.idle,
    };
    _setState(mapped);
  }

  Future<void> _handleLocalRealtimeCommand(String text) async {
    _setState(VoiceAgentState.thinking);
    try {
      await conversationController.quickAction(text);
    } catch (error) {
      await conversationController.showFallbackMessage(
        '我剛剛查詢時卡住了，可以再說一次嗎？',
      );
    } finally {
      if (_state != VoiceAgentState.error && _state != VoiceAgentState.idle) {
        _setState(VoiceAgentState.listening);
      }
    }
  }

  Future<void> _analyzeCompanionTranscript(
    String transcript,
    String turnId,
  ) async {
    try {
      final result = await companionEngineService.analyze(
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
      if (result.memory.shouldSave &&
          result.memory.candidate.trim().isNotEmpty) {
        unawaited(
          memoryController.extractMemory(
            sessionId: conversationController.activeSessionId,
            turnId: 'companion_$turnId',
            userText: transcript,
            aiReply: result.memory.candidate,
            emotion: result.emotion,
          ),
        );
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

  void _applyLocalCompanionFallback(String transcript, String turnId) {
    if (turnId != _latestCompanionTurnId) return;
    _emotion = detectEmotion(transcript);
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

  void _setState(VoiceAgentState newState) {
    _state = newState;
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
      case VoiceAgentState.speaking:
        _petExpression = 'speaking';
        _petAction = 'speak';
        petController.setMode(PetMode.talking, isSpeaking: true);
        break;
      case VoiceAgentState.error:
        petController.setMode(PetMode.sad);
        break;
      case VoiceAgentState.idle:
      case VoiceAgentState.connecting:
      case VoiceAgentState.connected:
        // Keep current pet state during transition.
        break;
    }
    notifyListeners();
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
    unawaited(_recoverToIdleAfterError(
      message: '目前連不到即時語音服務。你還是可以先用文字跟我聊天，或確認手機和電腦在同一個 Wi-Fi。',
    ));
  }

  Future<void> _recoverToIdleAfterError({String? message}) async {
    await realtimeVoiceService.stop();
    if (_state != VoiceAgentState.speaking) {
      _setState(VoiceAgentState.idle);
    }
    if (message != null && message.isNotEmpty) {
      petController.setModeAndMessage(PetMode.listening, message);
    }
  }

  @override
  void dispose() {
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
