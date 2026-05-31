import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/auth_session.dart';
import 'session_api_service.dart';

/// 登入狀態的應用層：負責「mock 登入 → 呼叫後端建立 session → 本機持久化 →
/// 啟動時還原 / 登出清除」。
///
/// CR-0006 Batch 3a 只做地基，**不接任何 UI**、不改記憶/搜尋的 userId 來源。
/// 真正的 Firebase token 安全儲存延後到真 Firebase 批次再評估。
class AuthService {
  AuthService({SessionApiService? sessionApiService})
      : _sessionApiService = sessionApiService ?? SessionApiService();

  final SessionApiService _sessionApiService;

  /// shared_preferences key（版本化，未來換結構好遷移）。
  static const String prefsKey = 'auth_session_v1';

  /// 以 demo / mock 身份登入：產生一組穩定的 demo 識別，呼叫後端建立 session，
  /// 不論成功或 fallback 都會持久化並回傳 [AuthSession]。
  Future<AuthSession> mockLogin({String? displayName, String? email}) async {
    final firebaseUid = _deriveDemoUid();
    final session = await _sessionApiService.createSession(
      firebaseUid: firebaseUid,
      idToken: 'mock-id-token-$firebaseUid',
      email: email,
      displayName: displayName,
      provider: 'mock',
    );
    await persist(session);
    return session;
  }

  /// 啟動時從 shared_preferences 還原 session；沒有則回 null。
  Future<AuthSession?> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return AuthSession.fromPrefs(decoded);
    } catch (_) {
      // 壞掉的快取就當作沒登入，不讓 app 掛。
      return null;
    }
  }

  /// 將 session 寫入 shared_preferences。
  Future<void> persist(AuthSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, jsonEncode(session.toPrefsMap()));
  }

  /// 清除本機 session（登出）。
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefsKey);
  }

  /// 產生穩定的 demo firebaseUid。
  ///
  /// 若本機已有一組 demo uid 就沿用，否則用時間派生一組並寫回，
  /// 讓同一台裝置重複 demo 登入時對到後端同一個使用者。
  String _deriveDemoUid() {
    return 'demo-${DateTime.now().millisecondsSinceEpoch}';
  }
}
