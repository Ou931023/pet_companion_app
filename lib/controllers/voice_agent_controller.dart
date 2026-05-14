import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/conversation_turn.dart';
import '../models/pet_status.dart';
import '../models/voice_agent_state.dart';
import '../services/ai_navigation_service.dart';
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
    required this.memoryController,
    required this.navigationService,
    required this.navigationController,
  });

  final ProfileController profileController;
  final PetController petController;
  final PetStatsController petStatsController;
  final ConversationController conversationController;
  final RealtimeVoiceService realtimeVoiceService;
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
  bool _skipNextAssistantText = false;

  VoiceAgentState get state => _state;
  UserEmotion get emotion => _emotion;
  String get petMood => _petMood;
  String get petExpression => _petExpression;
  String get petAction => _petAction;
  String get lastError => _lastError;
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
        final navigationIntent = navigationService.detect(event.payload);
        if (navigationIntent != null) {
          navigationController.navigateTo(navigationIntent.route);
          petController.setMessage(navigationIntent.reply);
          conversationController.appendExternalTurn(
            ConversationTurn(
              timestamp: DateTime.now(),
              userText: event.payload,
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
        if (conversationController.shouldHandleAsLocalCommand(event.payload)) {
          _pendingRealtimeUserText = '';
          _pendingRealtimeTurnId = '';
          _skipNextAssistantText = true;
          unawaited(_handleLocalRealtimeCommand(event.payload));
          return;
        }
        final renameResult = _tryHandleRenameIntent(event.payload);
        _emotion = detectEmotion(event.payload);
        debugPrint('[EMOTION] text=${event.payload} emotion=${_emotion.name}');
        _pendingRealtimeUserText = event.payload.trim();
        _pendingRealtimeEmotion = _emotion.name;
        _pendingRealtimeTurnId =
            'rt_${DateTime.now().microsecondsSinceEpoch.toString()}';
        _applyEmotionToPet();
        conversationController.appendExternalTurn(
          ConversationTurn(
            timestamp: DateTime.now(),
            userText: event.payload,
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
