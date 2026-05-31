/// 登入後由後端 `POST /api/auth/session` 回傳並在本機持久化的身份資料。
///
/// 這是 CR-0006 Batch 3a 的純資料層，**不接任何 UI**。後端契約見
/// `PROJECT_ARCHITECTURE.md` §10.2。所有欄位都儘量寬鬆解析，避免後端回傳
/// 缺欄或型別不符時讓 Demo 掛掉。
class AuthSession {
  const AuthSession({
    required this.userId,
    required this.elderId,
    required this.bindingStatus,
    required this.authMode,
    required this.isNewUser,
    this.role,
    this.bindingDeadline,
  });

  /// 後端 users.id（mock 模式 fallback 為 'default_user'）。
  final String userId;

  /// 後端 elders.id；下游記憶/搜尋會用到。未綁定時 fallback 'default_user'。
  final String elderId;

  /// 'pending' | 'bound' | 'expired'。
  final String bindingStatus;

  /// 'firebase' | 'mock'。mock 表示後端未設定 Firebase、以 demo 模式採信。
  final String authMode;

  /// 此次 session 是否建立了新使用者。
  final bool isNewUser;

  /// 'elder' | 'caregiver' | 'admin'，後端有帶才有值。
  final String? role;

  /// 綁定截止時間（ISO8601 字串，可能為 null）。以字串保存避免解析失敗。
  final String? bindingDeadline;

  /// 後端未綁定 / mock 時共用的 fallback 識別。
  static const String fallbackUserId = 'default_user';

  /// 由後端 `POST /api/auth/session` 的 JSON response 解析。
  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      userId: _readString(json['userId'], fallback: fallbackUserId),
      elderId: _readString(json['elderId'], fallback: fallbackUserId),
      bindingStatus: _readString(json['bindingStatus'], fallback: 'pending'),
      authMode: _readString(json['authMode'], fallback: 'mock'),
      isNewUser: json['isNewUser'] == true,
      role: _readNullableString(json['role']),
      bindingDeadline: _readNullableString(json['bindingDeadline']),
    );
  }

  /// 由 shared_preferences 存的扁平 map 還原。
  factory AuthSession.fromPrefs(Map<String, dynamic> prefs) {
    return AuthSession.fromJson(prefs);
  }

  /// 持久化用的扁平 map（與 fromPrefs 對稱）。
  Map<String, dynamic> toPrefsMap() => toJson();

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'elderId': elderId,
      'bindingStatus': bindingStatus,
      'authMode': authMode,
      'isNewUser': isNewUser,
      if (role != null) 'role': role,
      if (bindingDeadline != null) 'bindingDeadline': bindingDeadline,
    };
  }

  /// 後端不可用 / 解析失敗時使用的 demo fallback session，
  /// 讓 Demo 不被擋住。
  factory AuthSession.mockFallback() {
    return const AuthSession(
      userId: fallbackUserId,
      elderId: fallbackUserId,
      bindingStatus: 'pending',
      authMode: 'mock',
      isNewUser: false,
    );
  }

  AuthSession copyWith({
    String? userId,
    String? elderId,
    String? bindingStatus,
    String? authMode,
    bool? isNewUser,
    String? role,
    String? bindingDeadline,
  }) {
    return AuthSession(
      userId: userId ?? this.userId,
      elderId: elderId ?? this.elderId,
      bindingStatus: bindingStatus ?? this.bindingStatus,
      authMode: authMode ?? this.authMode,
      isNewUser: isNewUser ?? this.isNewUser,
      role: role ?? this.role,
      bindingDeadline: bindingDeadline ?? this.bindingDeadline,
    );
  }

  static String _readString(dynamic value, {required String fallback}) {
    if (value is String && value.trim().isNotEmpty) return value;
    if (value != null && value is! String) {
      final asString = value.toString().trim();
      if (asString.isNotEmpty) return asString;
    }
    return fallback;
  }

  static String? _readNullableString(dynamic value) {
    if (value is String && value.trim().isNotEmpty) return value;
    if (value != null && value is! String) {
      final asString = value.toString().trim();
      if (asString.isNotEmpty) return asString;
    }
    return null;
  }
}
