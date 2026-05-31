import 'package:flutter/foundation.dart';

import '../models/auth_session.dart';
import '../services/auth/auth_service.dart';

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

  AuthStatus get status => _status;
  AuthSession? get session => _session;

  bool get isAuthenticated => _status == AuthStatus.authenticated;

  /// 下游記憶/搜尋用的 elderId；未登入 fallback 'default_user'。
  String get currentElderId =>
      _session?.elderId ?? AuthSession.fallbackUserId;

  /// 目前 userId；未登入 fallback 'default_user'。
  String get currentUserId =>
      _session?.userId ?? AuthSession.fallbackUserId;

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
      _setStatus(AuthStatus.error);
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
    _setStatus(AuthStatus.unauthenticated);
  }

  void _setStatus(AuthStatus next) {
    _status = next;
    notifyListeners();
  }
}
