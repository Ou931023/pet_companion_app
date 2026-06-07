class AppConfig {
  /// 執行環境：`development` / `staging` / `production`。
  ///
  /// production build 透過 `--dart-define=APP_ENV=production` 指定。
  /// production 下會強制關閉開發面板、Demo 登入與 mock service 注入，
  /// 並要求 [apiBaseUrl] 指向正式網域（見 [isApiBaseUrlProductionSafe]）。
  static const String appEnv = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'development',
  );

  /// 是否為正式環境。集中判斷，避免各處各自比對字串。
  static bool get isProduction => appEnv == 'production';

  /// 正式對外 API base URL。
  ///
  /// 新命名 `API_BASE_URL` 為主；舊命名 `BACKEND_BASE_URL` 保留為可讀別名
  /// （未設定 `API_BASE_URL` 時回退讀取），預設為本機開發位址。
  /// UI 頁面一律從這裡取，不得硬編 base URL。
  static const String backendBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: String.fromEnvironment(
      'BACKEND_BASE_URL',
      defaultValue: 'http://127.0.0.1:3001',
    ),
  );

  /// [backendBaseUrl] 的對外語意別名（CR-0034 統一命名）。
  static String get apiBaseUrl => backendBaseUrl;

  /// 是否允許注入 / 使用 mock service（mock STT / mock AI / mock shop 等）。
  ///
  /// 預設 false；開發 / 測試需要時用 `--dart-define=ALLOW_MOCK_SERVICES=true`。
  /// production 一律不得使用，請改用 [mockServicesEnabled] 取得實際結果。
  static const bool allowMockServices = bool.fromEnvironment(
    'ALLOW_MOCK_SERVICES',
    defaultValue: false,
  );

  /// 實際是否啟用 mock service：production 一律 false（強制走正式路徑）。
  static bool get mockServicesEnabled => allowMockServices && !isProduction;

  /// 是否在登入頁顯示 Demo 快速登入按鈕（原始開關）。
  ///
  /// **正式展示 / 截圖預設為 false**（登入頁只露 Google / Email / 建立帳號，
  /// 不出現測試感按鈕）。開發 / 測試需要 Demo 備援時，用
  /// `--dart-define=SHOW_DEMO_LOGIN=true` 開啟。
  /// 注意：即使隱藏，`AuthController.loginAsDemoUser()` 仍保留，能力不刪。
  /// 實際是否顯示請用 [demoLoginVisible]（production 一律隱藏）。
  static const bool showDemoLoginButton = bool.fromEnvironment(
    'SHOW_DEMO_LOGIN',
    defaultValue: false,
  );

  /// Demo 登入按鈕實際是否顯示：production 強制隱藏。
  static bool get demoLoginVisible => showDemoLoginButton && !isProduction;
  static const String defaultSttProxyUrl = '$backendBaseUrl/api/stt/transcribe';
  static const String realtimeSessionUrl =
      '$backendBaseUrl/api/realtime/session';
  static const String realtimeCallUrl = '$backendBaseUrl/api/realtime/call';
  static const String careMallUrl = String.fromEnvironment(
    'CARE_MALL_URL',
    defaultValue: 'http://127.0.0.1:5500',
  );

  /// 是否顯示開發用面板（Realtime Diagnostics / Companion Debug Panel /
  /// AI Agent 工具測試）的原始開關。預設 false，Demo build 保持隱藏；
  /// 開發時用 --dart-define=SHOW_DEV_PANELS=true 啟用。
  /// 實際是否顯示請用 [devPanelsVisible]（production 一律隱藏）。
  static const bool showDevPanels = bool.fromEnvironment('SHOW_DEV_PANELS');

  /// 開發面板實際是否顯示：production 強制隱藏，長者不會看到工程診斷資訊。
  static bool get devPanelsVisible => showDevPanels && !isProduction;

  static const Set<String> legacyBackendHosts = {
    '127.0.0.1',
    'localhost',
    '10.0.2.2',
  };

  /// production 下 [apiBaseUrl] 是否安全（指向正式網域而非本機 / 空）。
  ///
  /// 非 production 永遠回 true（開發本機照常）。production 但 base URL 為空、
  /// 無法解析或仍指向 localhost / 127.0.0.1 / 10.0.2.2 時回 false，
  /// 由啟動層據此阻擋進入正式主流程，避免長者連到不存在的本機服務。
  static bool get isApiBaseUrlProductionSafe {
    if (!isProduction) return true;
    final uri = Uri.tryParse(backendBaseUrl.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return false;
    return !legacyBackendHosts.contains(uri.host);
  }

  static String realtimeCallUrlForSttProxy(String sttProxyUrl) {
    return _apiUrlFrom(sttProxyUrl, '/api/realtime/call');
  }

  static String healthUrlForSttProxy(String sttProxyUrl) {
    return _apiUrlFrom(sttProxyUrl, '/health');
  }

  static String apiBaseUrlForSttProxy(String sttProxyUrl) {
    return _apiUrlFrom(sttProxyUrl, '/api');
  }

  static String normalizeSttProxyUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || isLegacyDefaultUrl(trimmed)) {
      return defaultSttProxyUrl;
    }
    // When --dart-define=BACKEND_BASE_URL provides a real host (not the
    // 127.0.0.1 default), treat it as the source of truth and discard any
    // stored URL whose host differs — auto-recovers from stale LAN IPs
    // after Wi-Fi changes or rebuilds with a new LAN IP.
    final baseUri = Uri.tryParse(backendBaseUrl);
    final storedUri = Uri.tryParse(trimmed);
    if (baseUri != null &&
        storedUri != null &&
        baseUri.host.isNotEmpty &&
        baseUri.host != '127.0.0.1' &&
        storedUri.host != baseUri.host) {
      return defaultSttProxyUrl;
    }
    return trimmed;
  }

  static bool isLegacyDefaultUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null) return false;
    return legacyBackendHosts.contains(uri.host);
  }

  static String _apiUrlFrom(String sourceUrl, String apiPath) {
    final uri = Uri.tryParse(normalizeSttProxyUrl(sourceUrl));
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return '$backendBaseUrl$apiPath';
    }
    return uri.replace(path: apiPath, query: null, fragment: null).toString();
  }
}
