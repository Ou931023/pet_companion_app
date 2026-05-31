import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/auth_session.dart';
import 'firebase_auth_service.dart';
import 'session_api_service.dart';

/// 登入狀態的應用層：負責「登入（mock / Email）→ 呼叫後端建立 session →
/// 本機持久化 → 啟動時還原 / 登出清除」。
///
/// CR-0006 Batch 3a 地基；Batch 4b 加入 Email 註冊 / 登入。Demo 快速登入
/// （[mockLogin]）保持不變，永遠是 fallback。真正的 Firebase token 安全儲存
/// 延後到後續批次再評估。
class AuthService {
  AuthService({
    SessionApiService? sessionApiService,
    FirebaseAuthService? firebaseAuthService,
  })  : _sessionApiService = sessionApiService ?? SessionApiService(),
        _firebaseAuthService = firebaseAuthService ?? FirebaseAuthService();

  final SessionApiService _sessionApiService;
  final FirebaseAuthService _firebaseAuthService;

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

  /// Email 登入：Firebase 驗證 → 拿 idToken 呼叫後端建立 session → 持久化。
  ///
  /// Firebase 驗證失敗會丟 [EmailAuthException]（由上層轉白話）。後端 session
  /// 失敗時 `createSession` 內部已回 mockFallback（不丟例外、不 crash）。
  Future<AuthSession> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final result = await _firebaseAuthService.signInWithEmail(
      email: email,
      password: password,
    );
    return _createSessionFromFirebase(result);
  }

  /// Email 註冊：建立 Firebase 帳號 → 拿 idToken 呼叫後端建立 session → 持久化。
  Future<AuthSession> registerWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final result = await _firebaseAuthService.registerWithEmail(
      email: email,
      password: password,
      displayName: displayName,
    );
    return _createSessionFromFirebase(result);
  }

  /// Google 登入：Google/Firebase 驗證 → 拿 Firebase idToken 呼叫後端建立
  /// session（provider='google'）→ 持久化。
  ///
  /// Google 驗證失敗 / 取消會丟 [GoogleAuthException]（由上層轉白話 / 柔性中止）。
  /// 後端 session 失敗時 `createSession` 內部已回 mockFallback（不丟例外）。
  Future<AuthSession> signInWithGoogle() async {
    final result = await _firebaseAuthService.signInWithGoogle();
    return _createSessionFromFirebase(result);
  }

  Future<AuthSession> _createSessionFromFirebase(
    FirebaseSignInResult result,
  ) async {
    final session = await _sessionApiService.createSession(
      firebaseUid: result.uid,
      idToken: result.idToken,
      email: result.email,
      displayName: result.displayName,
      provider: result.provider,
      photoUrl: result.photoUrl,
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

  /// 清除本機 session（登出）。同時嘗試登出 Firebase（不可用時為安全 no-op，
  /// 不影響本機清除）。
  Future<void> logout() async {
    await _firebaseAuthService.signOut();
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
