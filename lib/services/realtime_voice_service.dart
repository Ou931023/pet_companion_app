import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_webrtc/flutter_webrtc.dart';

enum RealtimeEventType {
  state,
  userTranscript,
  assistantText,
  assistantAudioStart,
  assistantAudioEnd,
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

class RealtimeVoiceService {
  final _eventController = StreamController<RealtimeVoiceEvent>.broadcast();
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _eventsChannel;
  MediaStream? _localStream;
  final RTCVideoRenderer _remoteAudioRenderer = RTCVideoRenderer();
  bool _rendererReady = false;
  bool _isSpeaking = false;
  bool _isStopping = false;
  String _assistantBuffer = '';
  String _lastUserTranscript = '';

  Stream<RealtimeVoiceEvent> get events => _eventController.stream;

  Future<void> connect({
    required String realtimeCallUrl,
    required String petName,
    required String userId,
  }) async {
    _isStopping = false;
    _emit(RealtimeEventType.state, 'connecting');
    _log('Creating realtime call from $realtimeCallUrl for pet=$petName');
    try {
      await _ensureRendererInitialized();

      _peerConnection = await createPeerConnection({
        'sdpSemantics': 'unified-plan',
      });
      _peerConnection!.onConnectionState = (state) {
        _log('RTCPeerConnection connectionState: $state');
        final raw = state.toString().toLowerCase();
        if (raw.contains('connected')) {
          _emit(RealtimeEventType.state, 'connected');
          _emit(RealtimeEventType.state, 'listening');
          return;
        }
        if (raw.contains('failed') ||
            raw.contains('disconnected') ||
            raw.contains('closed')) {
          if (_isStopping) {
            _log('Ignore connection close event during manual stop');
            return;
          }
          _emit(
            RealtimeEventType.error,
            'Realtime 連線已中斷 (connectionState: $state)',
          );
        }
      };
      _peerConnection!.onIceConnectionState = (state) {
        _log('RTCPeerConnection iceConnectionState: $state');
      };
      _peerConnection!.onTrack = (event) {
        if (event.track.kind == 'audio' && event.streams.isNotEmpty) {
          final remoteStream = event.streams.first;
          final remoteAudioTrackCount = remoteStream.getAudioTracks().length;
          _log(
              'Received remote audio track from OpenAI (audioTracks=$remoteAudioTrackCount)');
          _remoteAudioRenderer.srcObject = remoteStream;
          unawaited(_ensureSpeakerphoneOn());
        }
      };

      _eventsChannel = await _peerConnection!.createDataChannel(
        'oai-events',
        RTCDataChannelInit()..ordered = true,
      );
      _eventsChannel!.onMessage = (message) {
        if (message.isBinary) return;
        _handleDataChannelEvent(message.text);
      };
      _eventsChannel!.onDataChannelState = (state) {
        _log('oai-events channel state: $state');
      };

      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });
      for (final track in _localStream!.getAudioTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
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

      final response = await http.post(
        Uri.parse(realtimeCallUrl).replace(
          queryParameters: {
            ...Uri.parse(realtimeCallUrl).queryParameters,
            'petName': petName.trim(),
            'userId': userId.trim(),
          },
        ),
        headers: {'Content-Type': 'application/sdp'},
        body: offerSdp,
      );
      _log('Realtime call status: ${response.statusCode}');
      if (response.statusCode >= 400) {
        throw Exception(
            'Realtime call failed: ${response.statusCode} ${response.body}');
      }

      final answerSdp = response.body;
      if (answerSdp.trim().isEmpty) {
        throw Exception('OpenAI returned empty SDP answer');
      }
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(answerSdp, 'answer'),
      );
      _emit(RealtimeEventType.state, 'connected');
      _emit(RealtimeEventType.state, 'listening');
    } catch (error) {
      _emit(RealtimeEventType.error, '無法建立 Realtime 連線：$error');
      rethrow;
    }
  }

  Future<void> startListening() async {
    if (_peerConnection == null) return;
    _assistantBuffer = '';
    _emit(RealtimeEventType.state, 'listening');
  }

  Future<void> stop() async {
    _isStopping = true;
    try {
      await _eventsChannel?.close();
      _eventsChannel = null;
      await _peerConnection?.close();
      _peerConnection = null;

      final stream = _localStream;
      if (stream != null) {
        for (final track in stream.getTracks()) {
          await track.stop();
        }
        await stream.dispose();
      }
      _localStream = null;
      _remoteAudioRenderer.srcObject = null;
      _assistantBuffer = '';
      _isSpeaking = false;
      _emit(RealtimeEventType.state, 'idle');
    } finally {
      _isStopping = false;
    }
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

    if (type == 'conversation.item.input_audio_transcription.completed') {
      _emitUserTranscriptFromEvent(map);
      return;
    }

    if (type == 'conversation.item.added' || type == 'conversation.item.done') {
      // Fallback for sessions where transcript appears on conversation item events.
      _emitUserTranscriptFromEvent(map);
      return;
    }

    if (type == 'input_audio_buffer.speech_started') {
      _emit(RealtimeEventType.state, 'listening');
      return;
    }

    if (type == 'input_audio_buffer.speech_stopped') {
      _emit(RealtimeEventType.state, 'thinking');
      return;
    }

    if (type == 'response.created') {
      if (!_isSpeaking) {
        _isSpeaking = true;
        _emit(RealtimeEventType.assistantAudioStart, '');
        _emit(RealtimeEventType.state, 'speaking');
      }
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
      _assistantBuffer += map['delta'] as String? ?? '';
      return;
    }

    if (type == 'response.output_audio.delta' ||
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

  void _emitUserTranscriptFromEvent(Map<String, dynamic> event) {
    final transcript = _extractUserTranscript(event);
    if (transcript.isEmpty) {
      return;
    }
    if (transcript == _lastUserTranscript) {
      return;
    }
    _lastUserTranscript = transcript;
    debugPrint('[TRANSCRIPT] userText=$transcript');
    _emit(RealtimeEventType.userTranscript, transcript);
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

  void _log(String message) {
    debugPrint('[RealtimeVoiceService] $message');
  }

  void _emit(RealtimeEventType type, String payload) {
    if (_eventController.isClosed) return;
    _eventController.add(RealtimeVoiceEvent(type: type, payload: payload));
  }

  void dispose() {
    _eventsChannel?.close();
    _peerConnection?.close();
    _localStream?.dispose();
    _remoteAudioRenderer.dispose();
    _eventController.close();
  }
}
