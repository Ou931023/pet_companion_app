import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'firebase_init.dart';

/// 應用層登入錯誤，**刻意不外洩 Firebase 的型別 / 訊息**。
///
/// 上層（AuthController）只看 [code]，再轉成長者看得懂的白話訊息。
/// 常見 code：`invalid-email` / `user-not-found` / `wrong-password` /
/// `invalid-credential` / `email-already-in-use` / `weak-password` /
/// `network-request-failed` / `unavailable`（Firebase 未初始化）/ `unknown`。
class EmailAuthException implements Exception {
  const EmailAuthException(this.code);

  final String code;

  @override
  String toString() => 'EmailAuthException($code)';
}

/// Google 登入的應用層錯誤（同樣不外洩 SDK 型別）。
///
/// [isCanceled] 代表「使用者自己取消」——上層應視為柔性中止、不當系統錯誤。
/// 其他常見 code：`interrupted` / `config` / `unavailable` / `unknown`。
class GoogleAuthException implements Exception {
  const GoogleAuthException(this.code);

  final String code;

  bool get isCanceled => code == 'canceled';

  @override
  String toString() => 'GoogleAuthException($code)';
}

/// 登入成功後要交給後端 `POST /api/auth/session` 的最小欄位集合。
///
/// CR-0006 Batch 4b / 4c 會在真正接上 Email / Google 後產生此結果，
/// 再由 `AuthService` 帶著 `idToken` 呼叫 `createSession`。
class FirebaseSignInResult {
  const FirebaseSignInResult({
    required this.uid,
    required this.idToken,
    required this.provider,
    this.email,
    this.displayName,
    this.photoUrl,
  });

  /// Firebase 使用者 uid。
  final String uid;

  /// Firebase ID Token，交給後端驗證。
  final String idToken;

  /// 'email' | 'google'。
  final String provider;

  final String? email;
  final String? displayName;
  final String? photoUrl;
}

/// Firebase / Google 登入的包裝層。
///
/// **CR-0006 Batch 4b**：Email 註冊 / 登入已實作；Google 登入仍為 4c 的 stub。
///
/// 這層刻意把 Firebase 細節（v7 `google_sign_in` 實例化 API、`FirebaseAuthException`
/// 等）封裝起來，讓上層 `AuthService` / `AuthController` 不直接依賴原生 SDK，
/// 並把錯誤統一轉成 [EmailAuthException]。測試可子類覆寫 Email 方法注入 fake，
/// 不需碰真 Firebase。
class FirebaseAuthService {
  FirebaseAuthService({FirebaseInitializer? initializer})
      : _initializer = initializer ?? FirebaseInitializer.instance;

  final FirebaseInitializer _initializer;

  /// Firebase 是否可用（初始化成功且有原生設定）。
  /// UI 可據此決定是否顯示真登入入口；不可用時仍保留 Demo 登入。
  bool get isAvailable => _initializer.isAvailable;

  /// Email 註冊。成功回 [FirebaseSignInResult]（含 idToken）；失敗丟
  /// [EmailAuthException]（已轉成應用層 code，不外洩 Firebase 型別）。
  Future<FirebaseSignInResult> registerWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    if (!_initializer.isAvailable) {
      throw const EmailAuthException('unavailable');
    }
    try {
      final credential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) throw const EmailAuthException('unknown');
      final trimmedName = displayName?.trim();
      if (trimmedName != null && trimmedName.isNotEmpty) {
        await user.updateDisplayName(trimmedName);
      }
      return _toResult(user, provider: 'email');
    } on FirebaseAuthException catch (error) {
      throw EmailAuthException(error.code);
    } on EmailAuthException {
      rethrow;
    } catch (_) {
      throw const EmailAuthException('unknown');
    }
  }

  /// Email 登入。成功回 [FirebaseSignInResult]；失敗丟 [EmailAuthException]。
  Future<FirebaseSignInResult> signInWithEmail({
    required String email,
    required String password,
  }) async {
    if (!_initializer.isAvailable) {
      throw const EmailAuthException('unavailable');
    }
    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) throw const EmailAuthException('unknown');
      return _toResult(user, provider: 'email');
    } on FirebaseAuthException catch (error) {
      throw EmailAuthException(error.code);
    } on EmailAuthException {
      rethrow;
    } catch (_) {
      throw const EmailAuthException('unknown');
    }
  }

  bool _googleInitialized = false;

  /// Google 登入（google_sign_in v7 實例化 API）。
  ///
  /// 流程：惰性 `initialize` → `authenticate()` 取 Google idToken →
  /// 轉 `GoogleAuthProvider` 憑證 → `FirebaseAuth.signInWithCredential` →
  /// 取 **Firebase** idToken 組 [FirebaseSignInResult]（送後端的是 Firebase token）。
  /// 失敗 / 取消一律轉 [GoogleAuthException]（取消為 `canceled`），不外洩 SDK 例外。
  Future<FirebaseSignInResult> signInWithGoogle() async {
    if (!_initializer.isAvailable) {
      throw const GoogleAuthException('unavailable');
    }
    try {
      await _ensureGoogleInitialized();
      final account = await GoogleSignIn.instance.authenticate();
      final googleIdToken = account.authentication.idToken;
      if (googleIdToken == null || googleIdToken.isEmpty) {
        throw const GoogleAuthException('unknown');
      }
      final credential = GoogleAuthProvider.credential(idToken: googleIdToken);
      final userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCredential.user;
      if (user == null) throw const GoogleAuthException('unknown');
      return _toResult(user, provider: 'google');
    } on GoogleSignInException catch (error) {
      throw GoogleAuthException(_mapGoogleCode(error.code));
    } on FirebaseAuthException catch (error) {
      throw GoogleAuthException(error.code);
    } on GoogleAuthException {
      rethrow;
    } catch (_) {
      throw const GoogleAuthException('unknown');
    }
  }

  /// 只需初始化一次 GoogleSignIn（v7 要求先 initialize 才能 authenticate）。
  Future<void> _ensureGoogleInitialized() async {
    if (_googleInitialized) return;
    await GoogleSignIn.instance.initialize();
    _googleInitialized = true;
  }

  /// 把 v7 的例外 code 收斂成上層好處理的應用層 code。
  String _mapGoogleCode(GoogleSignInExceptionCode code) {
    switch (code) {
      case GoogleSignInExceptionCode.canceled:
        return 'canceled';
      case GoogleSignInExceptionCode.interrupted:
      case GoogleSignInExceptionCode.uiUnavailable:
        return 'interrupted';
      case GoogleSignInExceptionCode.clientConfigurationError:
      case GoogleSignInExceptionCode.providerConfigurationError:
        return 'config';
      default:
        return 'unknown';
    }
  }

  /// 由 Firebase [User] 取出 idToken 組成上層要用的結果。
  Future<FirebaseSignInResult> _toResult(
    User user, {
    required String provider,
  }) async {
    final idToken = await user.getIdToken() ?? '';
    return FirebaseSignInResult(
      uid: user.uid,
      idToken: idToken,
      provider: provider,
      email: user.email,
      displayName: user.displayName,
      photoUrl: user.photoURL,
    );
  }

  /// 登出 Firebase。Firebase 不可用時為安全 no-op，
  /// 避免在未初始化情境觸發原生例外（本機 session 清除由
  /// `AuthService.logout` 負責，不依賴這裡成功）。
  Future<void> signOut() async {
    if (!_initializer.isAvailable) return;
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {
      // 忽略：登出失敗不影響本機登出流程。
    }
  }
}
