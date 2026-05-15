import 'voice_agent_state.dart';

enum RealtimeTimeoutType {
  connectionTimeout,
  transcriptTimeout,
  responseTimeout,
  ttsTimeout,
  reconnectTimeout,
}

class RealtimeTimeoutConfig {
  const RealtimeTimeoutConfig({
    this.connectionTimeout = const Duration(seconds: 10),
    this.transcriptTimeout = const Duration(seconds: 8),
    this.responseTimeout = const Duration(seconds: 14),
    this.ttsTimeout = const Duration(seconds: 24),
    this.reconnectTimeout = const Duration(seconds: 8),
  });

  final Duration connectionTimeout;
  final Duration transcriptTimeout;
  final Duration responseTimeout;
  final Duration ttsTimeout;
  final Duration reconnectTimeout;

  Duration durationFor(RealtimeTimeoutType type) {
    return switch (type) {
      RealtimeTimeoutType.connectionTimeout => connectionTimeout,
      RealtimeTimeoutType.transcriptTimeout => transcriptTimeout,
      RealtimeTimeoutType.responseTimeout => responseTimeout,
      RealtimeTimeoutType.ttsTimeout => ttsTimeout,
      RealtimeTimeoutType.reconnectTimeout => reconnectTimeout,
    };
  }
}

class RealtimeTimeoutRecoveryPlan {
  const RealtimeTimeoutRecoveryPlan({
    required this.type,
    required this.reason,
    required this.targetState,
    required this.fallbackReply,
    this.clearTurn = true,
    this.stopConnection = false,
    this.retryConnection = false,
  });

  final RealtimeTimeoutType type;
  final String reason;
  final VoiceAgentState targetState;
  final String fallbackReply;
  final bool clearTurn;
  final bool stopConnection;
  final bool retryConnection;
}

class RealtimeTimeoutPolicy {
  const RealtimeTimeoutPolicy();

  RealtimeTimeoutRecoveryPlan planFor(RealtimeTimeoutType type) {
    return switch (type) {
      RealtimeTimeoutType.connectionTimeout =>
        const RealtimeTimeoutRecoveryPlan(
          type: RealtimeTimeoutType.connectionTimeout,
          reason: 'connection_timeout',
          targetState: VoiceAgentState.recovering,
          fallbackReply: '連線有點不穩，我們再試一次。',
          stopConnection: true,
        ),
      RealtimeTimeoutType.transcriptTimeout =>
        const RealtimeTimeoutRecoveryPlan(
          type: RealtimeTimeoutType.transcriptTimeout,
          reason: 'transcript_timeout',
          targetState: VoiceAgentState.listening,
          fallbackReply: '我剛剛有點沒聽清楚，可以再跟我說一次嗎？',
        ),
      RealtimeTimeoutType.responseTimeout => const RealtimeTimeoutRecoveryPlan(
          type: RealtimeTimeoutType.responseTimeout,
          reason: 'response_timeout',
          targetState: VoiceAgentState.listening,
          fallbackReply: '我還在這裡陪你，我們慢慢說就好。',
        ),
      RealtimeTimeoutType.ttsTimeout => const RealtimeTimeoutRecoveryPlan(
          type: RealtimeTimeoutType.ttsTimeout,
          reason: 'tts_timeout',
          targetState: VoiceAgentState.listening,
          fallbackReply: '我還在這裡陪你，我們慢慢說就好。',
        ),
      RealtimeTimeoutType.reconnectTimeout => const RealtimeTimeoutRecoveryPlan(
          type: RealtimeTimeoutType.reconnectTimeout,
          reason: 'reconnect_timeout',
          targetState: VoiceAgentState.idle,
          fallbackReply: '剛剛連線有點不穩，我們再試一次。',
          stopConnection: true,
        ),
    };
  }
}
