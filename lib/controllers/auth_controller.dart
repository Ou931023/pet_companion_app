import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../models/auth_session.dart';
import '../services/auth/auth_service.dart';
import '../services/auth/firebase_auth_service.dart';
import '../services/auth/session_api_service.dart';
import '../utils/app_log.dart';

/// 登入流程的狀態機。
enum AuthStatus {
  /// 啟動還原中 / 登入呼叫中。
  loading,

  /// 沒有有效 session。
  unauthenticated,

  /// 已有有效 session。
  authenticated,

  /// 還原 / 登入發生非預期錯誤（仍不可讓 app 掛）。
  error,
}

/// 管理登入狀態的 Controller（ChangeNotifier）。
///
/// CR-0006 Batch 3a：純狀態層，**不接 UI、不接 app.dart auth gate**。
/// 未登入時 [currentElderId] / [currentUserId] 一律回 'default_user'，
/// 確保下游記憶/搜尋與 Demo 不會因為沒登入而壞掉。
class AuthController extends ChangeNotifier {
  AuthController({AuthService? authService})
      : _authService = authService ?? AuthService();

  final AuthService _authService;

  AuthStatus _status = AuthStatus.loading;
  AuthSession? _session;
  String? _errorMessage;

  AuthStatus get status => _status;
  AuthSession? get session => _session;

  /// 給 UI 顯示的白話錯誤訊息（**絕不放 Firebase exception 原文**）。
  /// 沒有錯誤時為 null。
  String? get errorMessage => _errorMessage;

  bool get isAuthenticated => _status == AuthStatus.authenticated;

  /// 下游記憶/搜尋/本機資料隔離用的 elderId。
  ///
  /// CR-0009：改以**登入方式**判斷 Demo vs 正式帳號（不靠後端 authMode，因為
  /// 後端在 mock 模式對正式 Email/Google 帳號也回 authMode='mock'）。
  /// - email / google / apple 登入 → 用 `session.elderId`（每帳號各自獨立）。
  /// - mock（Demo）/ 未登入 → 'default_user'（沿用既有 Demo 資料與記憶）。
  String get currentElderId => _resolveDownstreamId(_session?.elderId);

  /// 目前 userId（規則同 [currentElderId]）。
  String get currentUserId => _resolveDownstreamId(_session?.userId);

  /// 目前登入方式（'mock' | 'email' | 'google' | 'apple'），未登入為 null。
  /// 供 UI 決定刪除帳號時是否要先請使用者輸入密碼（Email）或重新 Google 驗證。
  String? get currentProvider => _session?.provider;

  /// 是否為「正式帳號」（以登入方式判斷）。
  bool get _isRealAccount {
    final provider = _session?.provider;
    return provider == 'email' || provider == 'google' || provider == 'apple';
  }

  /// CR-0045 B3：取得呼叫後端 `POST /api/care-alerts/notify` 需要的
  /// Bearer token（server 會由 token 權威推導 elderId）。
  ///
  /// - 正式帳號（email/google/apple，Firebase）→ 取「新的」Firebase idToken
  ///   （idToken 會過期，務必每次取新，不用舊存的）。
  /// - Demo / mock 帳號（僅非 production）→ `mock-id-token-<currentUserId>`，
  ///   dev / test 後端接受；**production 一律回 null，不偽造身分**。
  /// - 取不到（未登入 / Firebase 不可用 / 取得失敗）→ 回 null，呼叫端會略過通知。
  ///
  /// 全程 try/catch、不 throw，也**不會記錄完整 token**。
  Future<String?> resolveNotifyAuthToken() async {
    try {
      if (_isRealAccount) {
        return await _authService.currentIdToken();
      }
      // Demo / 未登入：production 不偽造；dev / test 用 mock token。
      if (AppConfig.isProduction) return null;
      return 'mock-id-token-$currentUserId';
    } catch (_) {
      AppLog.debug('[CARE_ALERT_NOTIFY] 取得身分權杖失敗（已忽略）。');
      return null;
    }
  }

  String _resolveDownstreamId(String? sessionId) {
    if (_isRealAccount && sessionId != null && sessionId.isNotEmpty) {
      return sessionId;
    }
    return AuthSession.fallbackUserId;
  }

  /// 啟動時還原既有 session。
  Future<void> restore() async {
    _setStatus(AuthStatus.loading);
    try {
      final restored = await _authService.restoreSession();
      if (restored != null) {
        _session = restored;
        _setStatus(AuthStatus.authenticated);
      } else {
        _session = null;
        _setStatus(AuthStatus.unauthenticated);
      }
    } catch (error) {
      AppLog.error('[AUTH] restore 失敗', error);
      _session = null;
      _setStatus(AuthStatus.error);
    }
  }

  /// 以 demo / mock 身份登入。
  Future<void> loginAsDemoUser({String? displayName, String? email}) async {
    _errorMessage = null;
    _setStatus(AuthStatus.loading);
    try {
      final session = await _authService.mockLogin(
        displayName: displayName,
        email: email,
      );
      _session = session;
      _setStatus(AuthStatus.authenticated);
    } catch (error) {
      AppLog.error('[AUTH] loginAsDemoUser 失敗', error);
      _errorMessage = '現在連線不太順，待會再試一次好嗎？';
      _setStatus(AuthStatus.error);
    }
  }

  /// Email 登入。
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _runEmailAuth(
      () => _authService.signInWithEmail(email: email, password: password),
    );
  }

  /// Email 註冊。
  Future<void> registerWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) {
    return _runEmailAuth(
      () => _authService.registerWithEmail(
        email: email,
        password: password,
        displayName: displayName,
      ),
    );
  }

  /// Google 登入。使用者「取消」視為柔性中止（不算錯誤、不留錯誤訊息、不卡死）；
  /// 其他失敗轉白話訊息。
  Future<void> signInWithGoogle() async {
    _errorMessage = null;
    _setStatus(AuthStatus.loading);
    try {
      _session = await _authService.signInWithGoogle();
      _setStatus(AuthStatus.authenticated);
    } on GoogleAuthException catch (error) {
      if (error.isCanceled) {
        // 使用者自己取消：回到未登入，不顯示錯誤、不擋後續操作。
        _errorMessage = null;
        _setStatus(AuthStatus.unauthenticated);
      } else {
        _errorMessage = _friendlyGoogleError(error.code);
        _setStatus(AuthStatus.error);
      }
    } on SessionApiException catch (error) {
      // CR-0037：Google 驗證成功但後端建立 session 失敗 → 白話錯誤＋可重試，
      // 不捏造登入。
      _errorMessage = _friendlySessionError(error.code);
      _setStatus(AuthStatus.error);
    } catch (error) {
      AppLog.error('[AUTH] google 登入失敗', error);
      _errorMessage = _friendlyGoogleError('unknown');
      _setStatus(AuthStatus.error);
    }
  }

  /// Apple 登入。使用者取消時回到登入頁，不顯示錯誤；其餘錯誤轉白話。
  Future<void> signInWithApple() async {
    _errorMessage = null;
    _setStatus(AuthStatus.loading);
    try {
      _session = await _authService.signInWithApple();
      _setStatus(AuthStatus.authenticated);
    } on AppleAuthException catch (error) {
      if (error.isCanceled) {
        _errorMessage = null;
        _setStatus(AuthStatus.unauthenticated);
      } else {
        _errorMessage = _friendlyAppleError(error.code);
        _setStatus(AuthStatus.error);
      }
    } on SessionApiException catch (error) {
      _errorMessage = _friendlySessionError(error.code);
      _setStatus(AuthStatus.error);
    } catch (error) {
      AppLog.error('[AUTH] apple 登入失敗', error);
      _errorMessage = _friendlyAppleError('unknown');
      _setStatus(AuthStatus.error);
    }
  }

  String _friendlyAppleError(String code) {
    switch (code) {
      case 'config':
      case 'unavailable':
        return 'Apple 登入目前無法使用，可以改用 Email 登入喔。';
      case 'network-request-failed':
        return '現在網路好像不太穩，待會再試一次好嗎？';
      default:
        return 'Apple 登入沒有成功，再試一次好嗎？';
    }
  }

  /// 寄送密碼重設信。此流程不改變登入狀態，避免 AuthGate 把表單換頁。
  /// 成功回 null；失敗回可直接顯示的白話訊息。
  Future<String?> sendPasswordResetEmail(String email) async {
    final normalized = email.trim();
    if (normalized.isEmpty) return '請先填一下 Email 喔。';
    try {
      await _authService.sendPasswordResetEmail(normalized);
      return null;
    } on EmailAuthException catch (error) {
      switch (error.code) {
        case 'invalid-email':
          return 'Email 的格式好像不太對，再檢查一下喔。';
        case 'network-request-failed':
          return '現在網路好像不太穩，待會再試一次好嗎？';
        case 'unavailable':
          return '密碼重設暫時無法使用，待會再試一次好嗎？';
        default:
          return '目前沒辦法寄出重設信，待會再試一次好嗎？';
      }
    } catch (error) {
      AppLog.error('[AUTH] password reset 失敗', error);
      return '目前沒辦法寄出重設信，待會再試一次好嗎？';
    }
  }

  /// Google 錯誤 code → 白話訊息。
  String _friendlyGoogleError(String code) {
    switch (code) {
      case 'interrupted':
        return '剛剛 Google 登入中斷了，再試一次好嗎？';
      case 'config':
      case 'unavailable':
        return 'Google 登入暫時還不能用，可以改用 Email 登入喔。';
      default:
        return '現在連線不太順，待會再試一次好嗎？';
    }
  }

  /// CR-0006 Batch 4d：Email 註冊（**不自動登入**）。
  ///
  /// 成功回 `null`；失敗回白話錯誤訊息。**刻意不改變 [status]**——註冊不等於
  /// 登入，使用者會被導回登入頁再自行登入，避免直接進 App。
  Future<String?> registerAccount({
    required String email,
    required String password,
  }) async {
    try {
      await _authService.registerAccountOnly(email: email, password: password);
      return null;
    } on EmailAuthException catch (error) {
      return _friendlyEmailError(error.code);
    } catch (error) {
      AppLog.error('[AUTH] registerAccount 失敗', error);
      return _friendlyEmailError('unknown');
    }
  }

  /// Email 註冊 / 登入的共用流程：loading → authenticated / error。
  /// 失敗一律轉成白話訊息，UI 不會看到 Firebase exception。
  Future<void> _runEmailAuth(Future<AuthSession> Function() action) async {
    _errorMessage = null;
    _setStatus(AuthStatus.loading);
    try {
      _session = await action();
      _setStatus(AuthStatus.authenticated);
    } on EmailAuthException catch (error) {
      _errorMessage = _friendlyEmailError(error.code);
      _setStatus(AuthStatus.error);
    } on SessionApiException catch (error) {
      // CR-0037：Firebase 驗證成功但後端建立 session 失敗 → 白話錯誤＋可重試，
      // 不捏造登入。
      _errorMessage = _friendlySessionError(error.code);
      _setStatus(AuthStatus.error);
    } catch (error) {
      AppLog.error('[AUTH] email auth 失敗', error);
      _errorMessage = _friendlyEmailError('unknown');
      _setStatus(AuthStatus.error);
    }
  }

  /// CR-0037：後端建立 session 失敗的 code → 長者看得懂的白話訊息。
  /// **絕不**顯示 SessionApiException / 後端原文。`invalid_token`（憑證失效）
  /// 與一般 server / network 區分，引導使用者重新登入。
  String _friendlySessionError(String code) {
    switch (code) {
      case 'invalid_token':
        return '登入的資料好像過期了，請重新登入一次好嗎？';
      case 'network':
        return '現在網路好像不太穩，待會再試一次好嗎？';
      case 'server':
      default:
        return '登入暫時有點忙不過來，待會再試一次好嗎？';
    }
  }

  /// 把 Firebase / 應用層錯誤 code 轉成長者看得懂的白話訊息。
  String _friendlyEmailError(String code) {
    switch (code) {
      case 'invalid-email':
        return 'Email 的格式好像不太對，再檢查一下喔。';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email 或密碼不太對，請再確認一次。';
      case 'email-already-in-use':
        return '這個 Email 已經註冊過了，直接登入就可以囉。';
      case 'weak-password':
        return '密碼長一點會比較安全，至少 6 個字喔。';
      case 'network-request-failed':
        return '現在網路好像不太穩，待會再試一次好嗎？';
      case 'unavailable':
        return '帳號登入暫時還不能用，可以先用「先進去陪伴」進去喔。';
      default:
        return '現在連線不太順，待會再試一次好嗎？';
    }
  }

  /// 登出：清除本機 session，回到未登入。
  Future<void> logout() async {
    try {
      await _authService.logout();
    } catch (error) {
      AppLog.error('[AUTH] logout 清除失敗（已忽略）', error);
    }
    _session = null;
    _errorMessage = null;
    _setStatus(AuthStatus.unauthenticated);
  }

  /// 刪除帳號：重新驗證 → 後端刪資料 → 刪 Firebase 帳號 → 清本機，回到未登入。
  ///
  /// - 成功回 `null` 且狀態切 unauthenticated（AuthGate 會回到登入頁）。
  /// - 失敗回白話訊息且**維持登入狀態**（例如密碼錯誤、需重新登入），UI 不會看到
  ///   Firebase 原文。
  /// - 使用者**取消** Google 重新驗證 → 柔性中止：回 `null` 但**維持登入**
  ///   （狀態不變），呼叫端應依 [isAuthenticated] 判斷是否真的要清本機資料。
  /// - Demo 帳號沒有 Firebase user → 等同登出，回 `null`。
  ///
  /// [password]：Email 帳號刪除前重新驗證用的密碼（Email 帳號必填，否則 Firebase
  /// 會回 `requires-recent-login`）。
  Future<String?> deleteAccount({String? password}) async {
    try {
      await _authService.deleteAccount(
        password: password,
        provider: _session?.provider,
      );
    } on EmailAuthException catch (error) {
      // 使用者自己取消 Google 重新驗證：不是錯誤，柔性中止、維持登入。
      if (error.code == 'canceled') return null;
      return _friendlyDeleteError(error.code);
    } on SessionApiException catch (error) {
      AppLog.error('[AUTH] backend deleteAccount 失敗', error);
      return _friendlyDeleteError(error.code);
    } catch (error) {
      AppLog.error('[AUTH] deleteAccount 失敗', error);
      return _friendlyDeleteError('unknown');
    }
    _session = null;
    _errorMessage = null;
    _setStatus(AuthStatus.unauthenticated);
    return null;
  }

  /// 刪除帳號錯誤 code → 長者看得懂的白話訊息。
  String _friendlyDeleteError(String code) {
    switch (code) {
      case 'wrong-password':
      case 'invalid-credential':
        return '密碼不太對喔，再輸入一次就可以刪除帳號。';
      case 'requires-recent-login':
        return '為了帳號安全，請先登出再重新登入一次，然後馬上刪除帳號喔。';
      case 'network-request-failed':
        return '現在網路好像不太穩，待會再試一次好嗎？';
      case 'account_delete_failed':
        return '目前還沒刪除完整，請檢查網路後再試一次。你的帳號和資料都還保留著。';
      default:
        return '現在沒辦法刪除帳號，待會再試一次好嗎？';
    }
  }

  void _setStatus(AuthStatus next) {
    _status = next;
    notifyListeners();
  }
}
