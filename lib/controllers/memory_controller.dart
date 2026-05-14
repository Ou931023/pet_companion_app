import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/memory_service.dart';

class MemoryController extends ChangeNotifier {
  MemoryController(this.memoryService) {
    _init();
  }

  final MemoryService memoryService;
  final Set<String> _processedTurnIds = <String>{};
  static const String _prefsUserKey = '_memory_user_id';
  String _userId = '';
  int? _lastGreetingSlot;
  List<Map<String, dynamic>> _memories = const [];
  bool _isLoadingMemories = false;
  String _memoryErrorMessage = '';

  String get userId => _userId.isEmpty ? 'default_user' : _userId;
  List<Map<String, dynamic>> get memories => List.unmodifiable(_memories);
  bool get isLoadingMemories => _isLoadingMemories;
  String get memoryErrorMessage => _memoryErrorMessage;

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = 'default_user';
    await prefs.setString(_prefsUserKey, _userId);
    notifyListeners();
  }

  Future<String?> getGreeting({
    required String petName,
    required bool isRealtimeActive,
  }) async {
    if (isRealtimeActive) return null;
    final localHour = DateTime.now().hour;
    final slot = _slotOf(localHour);
    if (_lastGreetingSlot == slot) return null;

    _lastGreetingSlot = slot;
    try {
      final greeting = await memoryService.getGreeting(
        userId: userId,
        petName: petName,
        localHour: localHour,
      );
      return greeting ?? _fallbackGreeting(petName, localHour);
    } catch (_) {
      return _fallbackGreeting(petName, localHour);
    }
  }

  Future<void> extractMemory({
    required String sessionId,
    required String turnId,
    required String userText,
    required String aiReply,
    required String emotion,
  }) async {
    final normalized = userText.trim();
    if (normalized.length < 4 ||
        normalized == '哈哈' ||
        normalized == '嗯' ||
        normalized == '嗯嗯' ||
        normalized == '謝謝') {
      return;
    }
    if (_processedTurnIds.contains(turnId)) return;
    _processedTurnIds.add(turnId);
    try {
      await memoryService.extractMemory(
        userId: userId,
        sessionId: sessionId,
        turnId: turnId,
        userText: userText,
        aiReply: aiReply,
        emotion: emotion,
      );
    } catch (_) {
      // Memory API failure should not break realtime conversation.
    }
  }

  Future<Map<String, dynamic>?> buildMemoryContext({
    required String userText,
    int limit = 5,
  }) async {
    final normalized = userText.trim();
    if (normalized.length < 4) return null;
    try {
      return await memoryService.buildMemoryContext(
        userId: userId,
        userText: normalized,
        limit: limit,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> forgetRecentMemory() async {
    try {
      await memoryService.forgetRecent(userId: userId);
    } catch (_) {}
  }

  Future<void> loadMemories() async {
    _isLoadingMemories = true;
    _memoryErrorMessage = '';
    notifyListeners();
    try {
      _memories = await memoryService.listMemories(userId: userId);
    } catch (_) {
      _memoryErrorMessage = '暫時無法讀取長期記憶，請稍後再試。';
      _memories = const [];
    } finally {
      _isLoadingMemories = false;
      notifyListeners();
    }
  }

  Future<bool> archiveMemory(Object memoryId) async {
    try {
      final ok = await memoryService.archiveMemory(
        userId: userId,
        memoryId: memoryId,
      );
      if (ok) {
        _memories = _memories
            .where((memory) => memory['id'].toString() != memoryId.toString())
            .toList();
        _memoryErrorMessage = '';
        notifyListeners();
      } else {
        _memoryErrorMessage = '暫時無法忘記這筆記憶。';
        notifyListeners();
      }
      return ok;
    } catch (_) {
      _memoryErrorMessage = '後端暫時無法連線，記憶沒有被刪除。';
      notifyListeners();
      return false;
    }
  }

  int _slotOf(int hour) {
    if (hour >= 5 && hour <= 10) return 0;
    if (hour >= 11 && hour <= 16) return 1;
    if (hour >= 17 && hour <= 23) return 2;
    return 3;
  }

  String _fallbackGreeting(String petName, int localHour) {
    if (localHour >= 5 && localHour <= 10) {
      return "早安，我是$petName，今天也陪你聊聊天。";
    }
    if (localHour >= 11 && localHour <= 16) {
      return "午安，我是$petName，今天過得還好嗎？";
    }
    if (localHour >= 17 && localHour <= 23) {
      return "晚安，我是$petName，今天辛苦了，我陪你一下。";
    }
    return "晚安，我是$petName，這麼晚了，要不要準備休息了呢？";
  }
}
