import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_webrtc/flutter_webrtc.dart';

enum RealtimeFailureType {
  none,
  backendUnavailable,
  missingApiKey,
  sessionCreateFailed,
  sdpExchangeFailed,
  peerConnectionFailed,
  dataChannelFailed,
  responseTimeout,
  microphonePermissionDenied,
  unknown,
}

extension RealtimeFailureTypeLabel on RealtimeFailureType {
  String get message {
    return switch (this) {
      RealtimeFailureType.none => '',
      RealtimeFailureType.backendUnavailable => '後端未啟動，請先啟動 Realtime backend。',
      RealtimeFailureType.missingApiKey =>
        'OpenAI API Key 未設定，請檢查 backend .env。',
      RealtimeFailureType.sessionCreateFailed => 'Realtime session 建立失敗。',
      RealtimeFailureType.sdpExchangeFailed => 'WebRTC SDP 交換失敗。',
      RealtimeFailureType.peerConnectionFailed => 'WebRTC peer connection 失敗。',
      RealtimeFailureType.dataChannelFailed => 'Realtime data channel 未開啟。',
      RealtimeFailureType.responseTimeout => 'Realtime 回應逾時，已回到聆聽狀態。',
      RealtimeFailureType.microphonePermissionDenied => '麥克風權限被拒絕，請到系統設定開啟權限。',
      RealtimeFailureType.unknown => 'Realtime 連線發生未知錯誤。',
    };
  }
}

class RealtimeFailure implements Exception {
  const RealtimeFailure(this.type, this.message);

  final RealtimeFailureType type;
  final String message;

  @override
  String toString() => '${type.name}: $message';
}

class RealtimeHealthStatus {
  const RealtimeHealthStatus({
    required this.ok,
    required this.hasOpenAiKey,
    required this.realtimeModel,
    required this.checkedAt,
    this.message = '',
  });

  final bool ok;
  final bool hasOpenAiKey;
  final String realtimeModel;
  final DateTime checkedAt;
  final String message;

  factory RealtimeHealthStatus.unavailable(String message) {
    return RealtimeHealthStatus(
      ok: false,
      hasOpenAiKey: false,
      realtimeModel: '',
      checkedAt: DateTime.now(),
      message: message,
    );
  }
}

enum RealtimeEventType {
  state,
  partialTranscript,
  finalTranscript,
  assistantText,
  assistantResponseStart,
  assistantResponseDone,
  assistantAudioStart,
  assistantAudioEnd,
  dataChannelOpen,
  dataChannelClosed,
  peerConnectionFailed,
  userSpeechStarted,
  userSpeechStopped,
  error,
}

class RealtimeVoiceEvent {
  const RealtimeVoiceEvent({
    required this.type,
    this.payload = '',
  });

  final RealtimeEventType type;
  final String payload;
}

class RealtimeConnectRequest {
  const RealtimeConnectRequest({
    required this.realtimeCallUrl,
    required this.petName,
    required this.userId,
    required this.companionContext,
    required this.languageHint,
    required this.replyLanguage,
    required this.mode,
    required this.attempt,
  });

  final String realtimeCallUrl;
  final String petName;
  final String userId;
  final String companionContext;
  final String languageHint;
  final String replyLanguage;
  final String mode;
  final int attempt;
}

class RealtimeVoiceService {
  RealtimeVoiceService({
    @visibleForTesting this.connectImplementationForTesting,
    @visibleForTesting this.eventSenderForTesting,
    @visibleForTesting this.healthCheckImplementationForTesting,
    this.dataChannelOpenTimeout = const Duration(seconds: 5),
  });

  @visibleForTesting
  final Future<void> Function(RealtimeConnectRequest request)?
      connectImplementationForTesting;

  @visibleForTesting
  final Future<void> Function(String payload)? eventSenderForTesting;

  @visibleForTesting
  final Future<RealtimeHealthStatus> Function(String healthUrl)?
      healthCheckImplementationForTesting;

  final Duration dataChannelOpenTimeout;
  final _eventController = StreamController<RealtimeVoiceEvent>.broadcast();
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _eventsChannel;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  final RTCVideoRenderer _remoteAudioRenderer = RTCVideoRenderer();
  final Queue<String> _pendingEventPayloads = Queue<String>();
  Future<void>? _connectInFlight;
  int _connectGeneration = 0;
  bool _rendererReady = false;
  bool _isSpeaking = false;
  bool _hasActiveAssistantResponse = false;
  bool _isStopping = false;
  bool _isDisposed = false;
  bool _dataChannelOpen = false;
  String _lastConnectionState = '';
  String _lastIceConnectionState = '';
  String _assistantBuffer = '';
  String _partialUserTranscriptBuffer = '';
  String _lastFinalUserTranscript = '';
  DateTime? _lastFinalTranscriptAt;
  Timer? _dataChannelOpenTimer;
  RealtimeFailureType _lastFailureType = RealtimeFailureType.none;
  String _lastFailureMessage = '';
  RealtimeHealthStatus? _lastHealthStatus;

  Stream<RealtimeVoiceEvent> get events => _eventController.stream;
  bool get isConnecting => _connectInFlight != null;
  bool get isDataChannelOpen => _dataChannelOpen;
  bool get isConnectionUsable =>
      _peerConnection != null &&
      _dataChannelOpen &&
      _isUsablePeerState(_lastConnectionState) &&
      (_lastIceConnectionState.isEmpty ||
          _isUsablePeerState(_lastIceConnectionState));
  String get lastConnectionState => _lastConnectionState;
  String get lastIceConnectionState => _lastIceConnectionState;
  String get dataChannelState => _dataChannelOpen
      ? 'open'
      : (_eventsChannel == null ? 'missing' : 'closed');
  RealtimeFailureType get lastFailureType => _lastFailureType;
  String get lastFailureMessage => _lastFailureMessage;
  RealtimeHealthStatus? get lastHealthStatus => _lastHealthStatus;

  Future<RealtimeHealthStatus> checkBackendHealth(String healthUrl) async {
    final tester = healthCheckImplementationForTesting;
    if (tester != null) {
      _lastHealthStatus = await tester(healthUrl);
      return _lastHealthStatus!;
    }
    try {
      final response = await http
          .get(Uri.parse(healthUrl))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode >= 500) {
        _recordFailure(
          RealtimeFailureType.backendUnavailable,
          'Health check failed: ${response.statusCode}',
        );
        return _lastHealthStatus =
            RealtimeHealthStatus.unavailable('後端未啟動或 health check 失敗');
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final status = RealtimeHealthStatus(
        ok: body['status'] == 'ok',
        hasOpenAiKey: body['hasOpenAiKey'] == true,
        realtimeModel: body['realtimeModel']?.toString() ?? '',
        checkedAt:
            DateTime.tryParse(body['time']?.toString() ?? '') ?? DateTime.now(),
        message: body['message']?.toString() ?? '',
      );
      _lastHealthStatus = status;
      if (!status.ok) {
        _recordFailure(RealtimeFailureType.backendUnavailable, status.message);
      } else if (!status.hasOpenAiKey) {
        _recordFailure(
          RealtimeFailureType.missingApiKey,
          RealtimeFailureType.missingApiKey.message,
        );
      }
      return status;
    } catch (error) {
      _recordFailure(
        RealtimeFailureType.backendUnavailable,
        'Backend health check failed: $error',
      );
      return _lastHealthStatus = RealtimeHealthStatus.unavailable('後端未啟動或無法連線');
    }
  }

  Future<void> connect({
    required String realtimeCallUrl,
    required String petName,
    required String userId,
    String companionContext = '',
    String languageHint = 'zh',
    String replyLanguage = 'zh-TW',
    String mode = '',
  }) async {
    if (_isDisposed) {
      throw StateError('RealtimeVoiceService has been disposed');
    }
    final existing = _connectInFlight;
    if (existing != null) {
      _log('connect ignored because a connection attempt is already running');
      return existing;
    }
    final generation = ++_connectGeneration;
    final future = _connectWithRetry(
      generation: generation,
      realtimeCallUrl: realtimeCallUrl,
      petName: petName,
      userId: userId,
      companionContext: companionContext,
      languageHint: languageHint,
      replyLanguage: replyLanguage,
      mode: mode,
    );
    _connectInFlight = future;
    try {
      await future;
    } finally {
      if (identical(_connectInFlight, future)) {
        _connectInFlight = null;
      }
    }
  }

  Future<void> _connectWithRetry({
    required int generation,
    required String realtimeCallUrl,
    required String petName,
    required String userId,
    required String companionContext,
    required String languageHint,
    required String replyLanguage,
    required String mode,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt += 1) {
      _isStopping = false;
      _emit(
          RealtimeEventType.state, attempt == 1 ? 'connecting' : 'recovering');
      _log(
        'Creating realtime call attempt=$attempt from $realtimeCallUrl for pet=$petName',
      );
      try {
        await _resetConnectionResources(emitIdle: false);
        _throwIfStaleConnect(generation);
        final testConnect = connectImplementationForTesting;
        if (testConnect != null) {
          await testConnect(RealtimeConnectRequest(
            realtimeCallUrl: realtimeCallUrl,
            petName: petName,
            userId: userId,
            companionContext: companionContext,
            languageHint: languageHint,
            replyLanguage: replyLanguage,
            mode: mode,
            attempt: attempt,
          ));
        } else {
          await _openConnectionOnce(
            realtimeCallUrl: realtimeCallUrl,
            petName: petName,
            userId: userId,
            companionContext: companionContext,
            languageHint: languageHint,
            replyLanguage: replyLanguage,
            mode: mode,
            generation: generation,
          );
        }
        _throwIfStaleConnect(generation);
        return;
      } catch (error) {
        lastError = error;
        _log('Realtime connect attempt=$attempt failed: $error');
        if (generation != _connectGeneration || _isDisposed) {
          await _resetConnectionResources(emitIdle: false);
          throw StateError('Realtime connection attempt was cancelled');
        }
        if (attempt < 3 && generation == _connectGeneration && !_isDisposed) {
          await _resetConnectionResources(emitIdle: false);
          await Future<void>.delayed(Duration(milliseconds: 250 * attempt));
          continue;
        }
        break;
      }
    }
    await _resetConnectionResources(emitIdle: false);
    final failure = lastError is RealtimeFailure
        ? lastError
        : RealtimeFailure(
            _lastFailureType == RealtimeFailureType.none
                ? RealtimeFailureType.sdpExchangeFailed
                : _lastFailureType,
            'Unable to establish realtime connection: $lastError',
          );
    _recordFailure(failure.type, failure.message);
    _emit(RealtimeEventType.error, failure.message);
    throw failure;
  }

  Future<void> _openConnectionOnce({
    required String realtimeCallUrl,
    required String petName,
    required String userId,
    required String companionContext,
    required String languageHint,
    required String replyLanguage,
    required String mode,
    required int generation,
  }) async {
    await _ensureRendererInitialized();

    _peerConnection = await createPeerConnection({
      'sdpSemantics': 'unified-plan',
    });
    _throwIfStaleConnect(generation);
    _peerConnection!.onConnectionState = (state) {
      _lastConnectionState = state.toString();
      _log('RTCPeerConnection connectionState: $state');
      _handlePeerState(_lastConnectionState);
    };
    _peerConnection!.onIceConnectionState = (state) {
      _lastIceConnectionState = state.toString();
      _log('RTCPeerConnection iceConnectionState: $state');
      _handlePeerState(_lastIceConnectionState);
    };
    _peerConnection!.onTrack = (event) {
      if (event.track.kind == 'audio' && event.streams.isNotEmpty) {
        final remoteStream = event.streams.first;
        final remoteAudioTrackCount = remoteStream.getAudioTracks().length;
        _log(
            'Received remote audio track from OpenAI (audioTracks=$remoteAudioTrackCount)');
        _remoteStream = remoteStream;
        _remoteAudioRenderer.srcObject = remoteStream;
        unawaited(_ensureSpeakerphoneOn());
      }
    };

    _eventsChannel = await _peerConnection!.createDataChannel(
      'oai-events',
      RTCDataChannelInit()..ordered = true,
    );
    _throwIfStaleConnect(generation);
    _eventsChannel!.onMessage = (message) {
      if (message.isBinary) return;
      _handleDataChannelEvent(message.text);
    };
    _eventsChannel!.onDataChannelState = (state) {
      _log('oai-events channel state: $state');
      _handleDataChannelState(state.toString());
    };
    _startDataChannelOpenTimer();

    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });
    } catch (error) {
      throw RealtimeFailure(
        RealtimeFailureType.microphonePermissionDenied,
        'Microphone permission denied or unavailable: $error',
      );
    }
    _throwIfStaleConnect(generation);
    for (final track in _localStream!.getAudioTracks()) {
      await _peerConnection!.addTrack(track, _localStream!);
      _throwIfStaleConnect(generation);
    }

    final offer = await _peerConnection!.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': false,
    });
    await _peerConnection!.setLocalDescription(offer);
    final offerSdp = offer.sdp;
    if (offerSdp == null || offerSdp.isEmpty) {
      throw Exception('Failed to create SDP offer');
    }

    final response = await http
        .post(
          Uri.parse(realtimeCallUrl).replace(
            queryParameters: {
              ...Uri.parse(realtimeCallUrl).queryParameters,
              'petName': petName.trim(),
              'userId': userId.trim(),
              if (companionContext.trim().isNotEmpty)
                'companionContext': companionContext.trim(),
              'languageHint': languageHint.trim(),
              'replyLanguage': replyLanguage.trim(),
              if (mode.trim().isNotEmpty) 'mode': mode.trim(),
            },
          ),
          headers: {'Content-Type': 'application/sdp'},
          body: offerSdp,
        )
        .timeout(const Duration(seconds: 12));
    _throwIfStaleConnect(generation);
    _log('Realtime call status: ${response.statusCode}');
    if (response.statusCode >= 400) {
      final type =
          response.statusCode == 401 || response.body.contains('API Key')
              ? RealtimeFailureType.missingApiKey
              : RealtimeFailureType.sdpExchangeFailed;
      throw RealtimeFailure(
        type,
        'Realtime call failed: ${response.statusCode} ${response.body}',
      );
    }

    final answerSdp = response.body;
    if (answerSdp.trim().isEmpty) {
      throw const RealtimeFailure(
        RealtimeFailureType.sdpExchangeFailed,
        'OpenAI returned empty SDP answer',
      );
    }
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(answerSdp, 'answer'),
    );
    _emit(RealtimeEventType.state, 'ready');
  }

  Future<void> startListening() async {
    if (_peerConnection == null) return;
    _assistantBuffer = '';
    _emit(RealtimeEventType.state, 'listening');
  }

  Future<void> updateCompanionContext(String companionContext) async {
    final normalized = companionContext.trim();
    if (normalized.isEmpty) return;
    try {
      await _sendEventPayload(jsonEncode({
        'type': 'session.update',
        'session': {
          'instructions': _instructionsWithCompanionContext(normalized),
        },
      }));
      _log('Companion context sent to realtime session');
    } catch (error) {
      _log('Unable to update companion context: $error');
    }
  }

  Future<void> stop() async {
    _connectGeneration += 1;
    _isStopping = true;
    try {
      await _resetConnectionResources(emitIdle: true);
    } finally {
      _isStopping = false;
    }
  }

  Future<void> disconnect() => stop();

  @visibleForTesting
  void handleDataChannelEventForTest(String payload) {
    _handleDataChannelEvent(payload);
  }

  @visibleForTesting
  void handleDataChannelStateForTest(String state) {
    _handleDataChannelState(state);
  }

  @visibleForTesting
  void handlePeerStateForTest(String state) {
    _lastConnectionState = state;
    _handlePeerState(state);
  }

  @visibleForTesting
  void handleIceStateForTest(String state) {
    _lastIceConnectionState = state;
    _handlePeerState(state);
  }

  @visibleForTesting
  Future<void> sendEventPayloadForTest(String payload) {
    return _sendEventPayload(payload);
  }

  @visibleForTesting
  int get pendingEventCountForTest => _pendingEventPayloads.length;

  @visibleForTesting
  void startDataChannelOpenTimerForTest() {
    _startDataChannelOpenTimer();
  }

  void _handleDataChannelEvent(String payload) {
    if (payload.trim().isEmpty) return;
    late final Map<String, dynamic> map;
    try {
      map = jsonDecode(payload) as Map<String, dynamic>;
    } catch (error) {
      _log('Failed to parse data channel payload: $error');
      return;
    }
    final type = map['type'] as String? ?? '';
    _log('Received event type: $type');

    if (type == 'session.updated') {
      return;
    }

    if (type == 'conversation.item.input_audio_transcription.delta' ||
        type == 'conversation.item.input_audio_transcription.partial' ||
        type == 'input_audio_buffer.transcription.delta' ||
        (type == 'response.audio_transcript.delta' &&
            !_hasActiveAssistantResponse)) {
      _emitUserTranscriptFromEvent(map, isFinal: false);
      return;
    }

    if (type == 'conversation.item.input_audio_transcription.completed') {
      _emitUserTranscriptFromEvent(map, isFinal: true);
      return;
    }

    if (type == 'conversation.item.added' || type == 'conversation.item.done') {
      // Fallback for sessions where transcript appears on conversation item events.
      _emitUserTranscriptFromEvent(map, isFinal: true);
      return;
    }

    if (type == 'input_audio_buffer.speech_started') {
      _emit(RealtimeEventType.userSpeechStarted, '');
      _emit(RealtimeEventType.state, 'listening');
      return;
    }

    if (type == 'input_audio_buffer.speech_stopped') {
      _emit(RealtimeEventType.userSpeechStopped, '');
      _emit(RealtimeEventType.state, 'transcribing');
      _emit(RealtimeEventType.state, 'thinking');
      return;
    }

    if (type == 'response.created') {
      _hasActiveAssistantResponse = true;
      _emit(RealtimeEventType.assistantResponseStart, '');
      _emit(RealtimeEventType.state, 'thinking');
      return;
    }

    if (type == 'response.output_text.delta' || type == 'response.text.delta') {
      if (!_isSpeaking) {
        _isSpeaking = true;
        _emit(RealtimeEventType.assistantAudioStart, '');
        _emit(RealtimeEventType.state, 'speaking');
      }
      _assistantBuffer += map['delta'] as String? ?? '';
      return;
    }

    if (type == 'response.output_audio_transcript.delta' ||
        type == 'response.audio_transcript.delta') {
      if (!_isSpeaking) {
        _isSpeaking = true;
        _emit(RealtimeEventType.assistantAudioStart, '');
        _emit(RealtimeEventType.state, 'speaking');
      }
      _assistantBuffer += map['delta'] as String? ?? '';
      return;
    }

    if (type == 'output_audio_buffer.started' ||
        type == 'response.output_audio.delta' ||
        type == 'response.audio.delta') {
      if (!_isSpeaking) {
        _isSpeaking = true;
        _emit(RealtimeEventType.assistantAudioStart, '');
        _emit(RealtimeEventType.state, 'speaking');
      }
      return;
    }

    if (type == 'response.done') {
      final text = _assistantBuffer.trim().isEmpty
          ? _extractReplyTextFromResponseDone(map).trim()
          : _assistantBuffer.trim();
      if (text.isNotEmpty) {
        _emit(RealtimeEventType.assistantText, text);
      }
      _assistantBuffer = '';
      _isSpeaking = false;
      _hasActiveAssistantResponse = false;
      _emit(RealtimeEventType.assistantResponseDone, '');
      _emit(RealtimeEventType.assistantAudioEnd, '');
      _log(
          'response.done received; keep realtime connection and return to listening');
      _emit(RealtimeEventType.state, 'listening');
      return;
    }

    if (type == 'error') {
      if (_isStopping) {
        _log('Ignore data channel error during manual stop');
        return;
      }
      _isSpeaking = false;
      final errorMap = map['error'] as Map<String, dynamic>?;
      final message = errorMap?['message'] as String? ?? 'Realtime API 發生錯誤';
      final code = errorMap?['code'] as String?;
      final errorType = errorMap?['type'] as String?;
      _log('Realtime error event: type=$errorType code=$code message=$message');
      _emit(RealtimeEventType.error, message);
    }
  }

  void _handleDataChannelState(String state) {
    final raw = state.toLowerCase();
    if (raw.contains('open')) {
      _dataChannelOpen = true;
      _cancelDataChannelOpenTimer();
      _emit(RealtimeEventType.dataChannelOpen, '');
      _emit(RealtimeEventType.state, 'ready');
      unawaited(_flushPendingEvents());
      return;
    }
    if (raw.contains('closed') || raw.contains('closing')) {
      _dataChannelOpen = false;
      if (_isStopping) {
        _log('Ignore data channel close event during manual stop');
        return;
      }
      _isSpeaking = false;
      _recordFailure(RealtimeFailureType.dataChannelFailed, state);
      _emit(RealtimeEventType.dataChannelClosed, state);
    }
  }

  void _handlePeerState(String state) {
    final raw = state.toLowerCase();
    if (_isClosedOrFailedState(raw)) {
      _dataChannelOpen = false;
      if (_isStopping) {
        _log('Ignore connection close event during manual stop');
        return;
      }
      _isSpeaking = false;
      _recordFailure(RealtimeFailureType.peerConnectionFailed, state);
      _emit(RealtimeEventType.peerConnectionFailed, state);
      return;
    }
    if (_isUsablePeerState(raw) && !_dataChannelOpen) {
      _emit(RealtimeEventType.state, 'connected');
    }
  }

  static bool _isClosedOrFailedState(String state) {
    final raw = state.toLowerCase();
    return raw.contains('failed') ||
        raw.contains('disconnected') ||
        raw.contains('closed');
  }

  static bool _isUsablePeerState(String state) {
    final raw = state.toLowerCase();
    return raw.contains('connected') || raw.contains('completed');
  }

  Future<void> _sendEventPayload(String payload) async {
    if (!_dataChannelOpen) {
      _pendingEventPayloads.add(payload);
      _log(
          'Data channel is not open; queued event (${_pendingEventPayloads.length})');
      return;
    }
    if (_isClosedOrFailedState(_lastConnectionState) ||
        _isClosedOrFailedState(_lastIceConnectionState)) {
      _dataChannelOpen = false;
      _pendingEventPayloads.add(payload);
      _log('Peer connection is closed or failed; queued event for reconnect');
      return;
    }
    final sender = eventSenderForTesting;
    if (sender != null) {
      await sender(payload);
      return;
    }
    final channel = _eventsChannel;
    if (channel == null) {
      _pendingEventPayloads.addFirst(payload);
      _dataChannelOpen = false;
      _log('Data channel missing while sending; queued event');
      return;
    }
    final state = channel.state?.toString().toLowerCase() ?? '';
    if (state.isNotEmpty && !state.contains('open')) {
      _pendingEventPayloads.addFirst(payload);
      _dataChannelOpen = false;
      _recordFailure(
        RealtimeFailureType.dataChannelFailed,
        'Data channel not open while sending: $state',
      );
      _log('Data channel state is $state; queued event');
      return;
    }
    await channel.send(RTCDataChannelMessage(payload));
  }

  Future<void> _flushPendingEvents() async {
    while (_dataChannelOpen && _pendingEventPayloads.isNotEmpty) {
      final payload = _pendingEventPayloads.removeFirst();
      try {
        await _sendEventPayload(payload);
      } catch (error) {
        _pendingEventPayloads.addFirst(payload);
        _log('Unable to flush queued realtime event: $error');
        return;
      }
    }
  }

  void _throwIfStaleConnect(int generation) {
    if (_isDisposed || generation != _connectGeneration) {
      throw StateError('Realtime connection attempt was cancelled');
    }
  }

  Future<void> _resetConnectionResources({required bool emitIdle}) async {
    _cancelDataChannelOpenTimer();
    _dataChannelOpen = false;
    _pendingEventPayloads.clear();
    _lastConnectionState = '';
    _lastIceConnectionState = '';

    final channel = _eventsChannel;
    _eventsChannel = null;
    if (channel != null) {
      try {
        await channel.close();
      } catch (error) {
        _log('Ignoring data channel close error: $error');
      }
    }

    final peerConnection = _peerConnection;
    _peerConnection = null;
    if (peerConnection != null) {
      try {
        await peerConnection.close();
      } catch (error) {
        _log('Ignoring peer connection close error: $error');
      }
      try {
        await peerConnection.dispose();
      } catch (error) {
        _log('Ignoring peer connection dispose error: $error');
      }
    }

    await _disposeStream(_localStream, stopTracks: true);
    _localStream = null;
    await _disposeStream(_remoteStream, stopTracks: false);
    _remoteStream = null;
    if (_rendererReady) {
      try {
        _remoteAudioRenderer.srcObject = null;
      } catch (error) {
        _log('Ignoring renderer reset error: $error');
      }
    }
    _assistantBuffer = '';
    _partialUserTranscriptBuffer = '';
    _lastFinalUserTranscript = '';
    _lastFinalTranscriptAt = null;
    _isSpeaking = false;
    _hasActiveAssistantResponse = false;
    if (emitIdle) {
      _emit(RealtimeEventType.state, 'idle');
    }
  }

  Future<void> _disposeStream(MediaStream? stream,
      {required bool stopTracks}) async {
    if (stream == null) return;
    if (stopTracks) {
      for (final track in stream.getTracks()) {
        try {
          await track.stop();
        } catch (error) {
          _log('Ignoring media track stop error: $error');
        }
      }
    }
    try {
      await stream.dispose();
    } catch (error) {
      _log('Ignoring media stream dispose error: $error');
    }
  }

  String _extractReplyTextFromResponseDone(Map<String, dynamic> event) {
    final response = event['response'] as Map<String, dynamic>?;
    final output = response?['output'];
    if (output is! List) return '';
    final buffer = StringBuffer();
    for (final item in output) {
      if (item is! Map<String, dynamic>) continue;
      final content = item['content'];
      if (content is! List) continue;
      for (final part in content) {
        if (part is! Map<String, dynamic>) continue;
        final text =
            (part['text'] as String?) ?? (part['transcript'] as String?) ?? '';
        if (text.isNotEmpty) {
          buffer.write(text);
        }
      }
    }
    return buffer.toString();
  }

  Future<void> _ensureRendererInitialized() async {
    if (_rendererReady) return;
    await _remoteAudioRenderer.initialize();
    _rendererReady = true;
  }

  Future<void> _ensureSpeakerphoneOn() async {
    try {
      await Helper.setSpeakerphoneOn(true);
      _log('Speakerphone enabled for realtime audio');
    } catch (error) {
      _log('Unable to enable speakerphone: $error');
    }
  }

  void _emitUserTranscriptFromEvent(
    Map<String, dynamic> event, {
    required bool isFinal,
  }) {
    final transcript = isFinal
        ? _extractUserTranscript(event)
        : _extractPartialUserTranscript(event);
    if (transcript.isEmpty) {
      if (isFinal) {
        _partialUserTranscriptBuffer = '';
      }
      return;
    }
    if (isFinal) {
      _partialUserTranscriptBuffer = '';
      final now = DateTime.now();
      final previousAt = _lastFinalTranscriptAt;
      if (transcript == _lastFinalUserTranscript &&
          previousAt != null &&
          now.difference(previousAt).abs() <= const Duration(seconds: 2)) {
        return;
      }
      _lastFinalUserTranscript = transcript;
      _lastFinalTranscriptAt = now;
    }
    debugPrint('[TRANSCRIPT] ${isFinal ? 'final' : 'partial'}=$transcript');
    _emit(
      isFinal
          ? RealtimeEventType.finalTranscript
          : RealtimeEventType.partialTranscript,
      transcript,
    );
  }

  String _extractUserTranscript(Map<String, dynamic> event) {
    final direct = (event['transcript'] as String?)?.trim();
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }

    final item = event['item'];
    if (item is! Map<String, dynamic>) return '';
    final role = item['role'] as String?;
    if (role != null && role != 'user') return '';

    final content = item['content'];
    if (content is! List) return '';
    final buffer = StringBuffer();
    for (final part in content) {
      if (part is! Map<String, dynamic>) continue;
      final text =
          ((part['transcript'] as String?) ?? (part['text'] as String?) ?? '')
              .trim();
      if (text.isNotEmpty) {
        if (buffer.isNotEmpty) buffer.write(' ');
        buffer.write(text);
      }
    }
    return buffer.toString().trim();
  }

  String _extractPartialUserTranscript(Map<String, dynamic> event) {
    final delta = (event['delta'] as String?)?.trim();
    if (delta != null && delta.isNotEmpty) {
      _partialUserTranscriptBuffer += delta;
      return _partialUserTranscriptBuffer.trim();
    }

    final transcript = _extractUserTranscript(event);
    if (transcript.isNotEmpty) {
      _partialUserTranscriptBuffer = transcript;
      return _partialUserTranscriptBuffer.trim();
    }

    return _partialUserTranscriptBuffer.trim();
  }

  void _log(String message) {
    debugPrint('[RealtimeVoiceService] $message');
  }

  void _emit(RealtimeEventType type, String payload) {
    if (_eventController.isClosed) return;
    _eventController.add(RealtimeVoiceEvent(type: type, payload: payload));
  }

  void _startDataChannelOpenTimer() {
    _cancelDataChannelOpenTimer();
    _dataChannelOpenTimer = Timer(dataChannelOpenTimeout, () {
      if (_dataChannelOpen || _isStopping || _isDisposed) return;
      _recordFailure(
        RealtimeFailureType.dataChannelFailed,
        'Data channel did not open within ${dataChannelOpenTimeout.inSeconds}s',
      );
      _emit(RealtimeEventType.error,
          RealtimeFailureType.dataChannelFailed.message);
    });
  }

  void _cancelDataChannelOpenTimer() {
    _dataChannelOpenTimer?.cancel();
    _dataChannelOpenTimer = null;
  }

  void _recordFailure(RealtimeFailureType type, String message) {
    _lastFailureType = type;
    _lastFailureMessage = message;
  }

  String _instructionsWithCompanionContext(String context) {
    final outputGuidance = _outputLanguageGuidance(context);
    return '''
你是長者陪伴寵物，不是一般助理。
你負責即時、自然、不中斷的口語陪伴回應。
使用者不一定會直接說出「孤單、難過、焦慮」等字眼，你要從語意中理解可能的陪伴需求。
不要武斷地說「你就是孤單」。
回覆要簡短、自然、像陪在身邊的寵物。
每次最多問一個問題。
不要像客服，不要像老師，不要做醫療診斷。
如果 languageHint=taigi，可以用台灣長者自然聽得懂的語氣回應；不要硬翻成不自然台語。
如果台語 transcript 不完整，請溫和追問，不要假裝完全聽懂。
$outputGuidance

Companion Engine 目前分析：
$context

請優先遵守 nextStrategy，但不要提到 Companion Engine、分析系統或欄位名稱。
''';
  }

  String _outputLanguageGuidance(String context) {
    final replyLanguage =
        RegExp(r'replyLanguage=([^\n\r]+)').firstMatch(context)?.group(1) ?? '';
    return switch (replyLanguage.trim()) {
      'mixed-zh-taigi' => '請使用台語口吻搭配繁體中文漢字回覆，不要使用大量羅馬拼音；語氣要自然、長輩聽得懂。',
      'taigi' => '請盡量使用自然台語口吻回覆，必要時混合繁體中文讓長輩聽得懂；不要使用艱深台語字或大量羅馬拼音。',
      _ => '請用繁體中文自然回覆。',
    };
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _connectGeneration += 1;
    _isStopping = true;
    _cancelDataChannelOpenTimer();
    unawaited(_resetConnectionResources(emitIdle: false));
    if (_rendererReady) {
      _remoteAudioRenderer.dispose();
    }
    _eventController.close();
  }
}
