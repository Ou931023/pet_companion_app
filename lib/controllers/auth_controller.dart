import 'package:flutter/foundation.dart';

import '../models/auth_session.dart';
import '../services/auth/auth_service.dart';
import '../services/auth/firebase_auth_service.dart';

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

  /// 是否為「正式帳號」（以登入方式判斷）。
  bool get _isRealAccount {
    final provider = _session?.provider;
    return provider == 'email' || provider == 'google' || provider == 'apple';
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
      debugPrint('[AUTH] restore 失敗：$error');
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
      debugPrint('[AUTH] loginAsDemoUser 失敗：$error');
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
    } catch (error) {
      debugPrint('[AUTH] google 登入失敗：$error');
      _errorMessage = _friendlyGoogleError('unknown');
      _setStatus(AuthStatus.error);
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
      debugPrint('[AUTH] registerAccount 失敗：$error');
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
    } catch (error) {
      debugPrint('[AUTH] email auth 失敗：$error');
      _errorMessage = _friendlyEmailError('unknown');
      _setStatus(AuthStatus.error);
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
      debugPrint('[AUTH] logout 清除失敗（已忽略）：$error');
    }
    _session = null;
    _errorMessage = null;
    _setStatus(AuthStatus.unauthenticated);
  }

  void _setStatus(AuthStatus next) {
    _status = next;
    notifyListeners();
  }
}
