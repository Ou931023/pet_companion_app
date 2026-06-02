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
    // CR-0009：標記為 demo 登入（provider='mock'）→ 下游用 default_user 空間。
    final stamped = session.copyWith(provider: 'mock');
    await persist(stamped);
    return stamped;
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

  /// CR-0006 Batch 4d：只建立 Firebase 帳號，**不自動登入**。
  ///
  /// 不建立後端 session、不持久化、並登出 Firebase；使用者註冊完要回登入頁
  /// 再用 Email / 密碼登入（後端 user/elder 會在首次登入時建立）。
  /// 失敗（如 email 已被使用）會丟 [EmailAuthException]，由上層轉白話。
  Future<void> registerAccountOnly({
    required String email,
    required String password,
    String? displayName,
  }) async {
    await _firebaseAuthService.registerWithEmail(
      email: email,
      password: password,
      displayName: displayName,
    );
    // 註冊不等於登入：登出剛建立的 Firebase session，避免自動進 App。
    await _firebaseAuthService.signOut();
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
    // CR-0009：標記為正式登入（email/google）→ 下游用 session.elderId 隔離，
    // 即使後端在 mock 模式回 authMode='mock' 也能依登入方式正確判斷。
    var stamped = session.copyWith(provider: result.provider);

    // 後端不可達時（例如實機連不到 127.0.0.1 的後端）createSession 會回
    // mockFallback（elderId/userId = 'default_user'）。正式帳號**不該**落在
    // default_user（會和其他帳號 + Demo 共用本機資料），所以改用 Firebase uid
    // 當穩定且每帳號唯一的隔離 key，確保不依賴後端也能正確隔離。
    final needsLocalId = stamped.elderId.isEmpty ||
        stamped.elderId == AuthSession.fallbackUserId;
    if (needsLocalId && result.uid.isNotEmpty) {
      stamped = stamped.copyWith(elderId: result.uid, userId: result.uid);
    }

    await persist(stamped);
    return stamped;
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

  /// 刪除帳號：把帳號「刪乾淨」。流程（任一步失敗都會丟 [EmailAuthException]，
  /// 由上層轉白話，**此時不清除本機 session**，讓使用者維持登入可重試）：
  ///
  /// 1. **重新驗證**（Firebase 對刪除等敏感操作要求近期登入）：
  ///    - [password] 有值（Email 帳號）→ 用密碼重新驗證。
  ///    - [provider] == 'google' → 重新跑一次 Google 登入驗證（使用者可取消）。
  /// 2. 取目前 Firebase user 的 uid + idToken，呼叫**後端刪除**該帳號的所有
  ///    資料（使用者 / 長者 / 長期記憶 / Care Alert）。後端不可達時為 best-effort
  ///    （不丟例外、不擋住帳號刪除）。
  /// 3. **刪除 Firebase 帳號**（讓同一個 Email 之後可以重新註冊）。
  /// 4. 清除本機 session。
  ///
  /// Demo / Firebase 不可用時：重新驗證與 `deleteCurrentUser` 皆為 no-op、
  /// 後端步驟略過（拿不到 uid），等同登出並清本機。
  Future<void> deleteAccount({String? password, String? provider}) async {
    // 1. 重新驗證（讓步驟 3 的刪除不會落入 requires-recent-login）。
    if (password != null && password.isNotEmpty) {
      await _firebaseAuthService.reauthenticateWithPassword(password);
    } else if (provider == 'google') {
      await _firebaseAuthService.reauthenticateWithGoogle();
    }

    // 2. 後端刪資料（best-effort：失敗只記錄，不擋住帳號刪除）。
    final authInfo = await _firebaseAuthService.currentUserAuthInfo();
    if (authInfo != null && authInfo.idToken.isNotEmpty) {
      await _sessionApiService.deleteAccount(
        firebaseUid: authInfo.uid,
        idToken: authInfo.idToken,
      );
    }

    // 3. 刪除 Firebase 帳號（失敗會丟 EmailAuthException）。
    await _firebaseAuthService.deleteCurrentUser();

    // 4. 清除本機 session。
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
