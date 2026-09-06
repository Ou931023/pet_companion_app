class AppConfig {
  /// 執行環境：`development` / `staging` / `production`。
  ///
  /// 正式產品預設即為 production；本機開發才需明確指定
  /// `--dart-define=APP_ENV=development`。
  /// production 下會強制關閉開發面板、Demo 登入與 mock service 注入，
  /// 並要求 [apiBaseUrl] 指向正式網域（見 [isApiBaseUrlProductionSafe]）。
  static const String appEnv = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'production',
  );

  /// 是否為正式環境。集中判斷，避免各處各自比對字串。
  static bool get isProduction => appEnv == 'production';

  /// 正式對外 API base URL。
  ///
  /// 新命名 `API_BASE_URL` 為主；舊命名 `BACKEND_BASE_URL` 保留為可讀別名
  /// （未設定 `API_BASE_URL` 時回退讀取）。預設為正式 Render 後端，避免
  /// 從 Xcode Archive / Android Studio release 時漏帶 dart-define 而連到本機。
  /// UI 頁面一律從這裡取，不得硬編 base URL。
  static const String backendBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: String.fromEnvironment(
      'BACKEND_BASE_URL',
      defaultValue: 'https://ai-companion-api-1gm7.onrender.com',
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

  /// 是否允許「所有寵物外觀預設已擁有」的原始開關。
  ///
  /// 這是成果展示 / 內部測試用旗標；正式上架版不得把付費 / 解鎖流程
  /// 硬改成全免費。需要展示全部寵物時，用
  /// `--dart-define=FREE_ALL_PET_SKINS=true` 開啟。
  /// 實際是否啟用請用 [freeAllPetSkinsEnabled]（production 一律關閉）。
  static const bool freeAllPetSkins = bool.fromEnvironment(
    'FREE_ALL_PET_SKINS',
    defaultValue: false,
  );

  /// Demo 全寵物免費實際是否啟用：production 強制關閉。
  static bool get freeAllPetSkinsEnabled => freeAllPetSkins && !isProduction;

  /// 是否在登入頁顯示 Demo 快速登入按鈕（原始開關）。
  ///
  /// **正式展示 / 截圖預設為 false**（登入頁只露 Google、Email、建立帳號，
  /// iOS 另顯示 Apple；不出現測試感按鈕）。開發 / 測試需要 Demo 備援時，用
  /// `--dart-define=SHOW_DEMO_LOGIN=true` 開啟。
  /// 注意：即使隱藏，`AuthController.loginAsDemoUser()` 仍保留，能力不刪。
  /// 實際是否顯示請用 [demoLoginVisible]（production 一律隱藏）。
  static const bool showDemoLoginButton = bool.fromEnvironment(
    'SHOW_DEMO_LOGIN',
    defaultValue: false,
  );

  /// Demo 登入按鈕實際是否顯示：production 強制隱藏。
  static bool get demoLoginVisible => showDemoLoginButton && !isProduction;

  /// 是否顯示第三方登入（Google / Apple）的原始開關。
  ///
  /// Google 與 Apple 已走 Firebase 正式登入；預設顯示，必要時可由 build flag
  /// 暫停入口。production 不再強制隱藏，避免正式使用者只能依賴 Email。
  static const bool showSocialSignIn = bool.fromEnvironment(
    'SHOW_SOCIAL_SIGN_IN',
    defaultValue: true,
  );

  /// Google / Apple 登入入口實際是否顯示。
  static bool get socialSignInVisible => showSocialSignIn;

  /// 是否顯示「照護用品商城」入口（marketplace）的原始開關。
  ///
  /// CR-0056（裁決 A2）：marketplace 能力保留，但正式版**完全隱藏入口**，
  /// 避免長者撞到「功能準備中」死路頁，也避免 App Store 2.1 placeholder 風險。
  /// dev / test 預設可見；如需在開發時隱藏可用
  /// `--dart-define=SHOW_MARKETPLACE=false`。
  /// 能力與路由（[AppRoute.marketplace]）不刪，僅隱藏入口。
  /// 實際是否顯示請用 [marketplaceVisible]（production 一律隱藏）。
  static const bool showMarketplace = bool.fromEnvironment(
    'SHOW_MARKETPLACE',
    defaultValue: true,
  );

  /// marketplace 入口實際是否顯示：production 強制隱藏。
  static bool get marketplaceVisible => showMarketplace && !isProduction;

  /// 是否顯示「今日任務」入口（dailyCareTask）的原始開關。
  ///
  /// 日常照護任務、照片驗證與正式 PostgreSQL API 已完成，因此 production
  /// 可以顯示；如需在特定 build 暫停入口可用
  /// `--dart-define=SHOW_DAILY_CARE_TASKS=false`。
  /// 能力與路由（[AppRoute.dailyCareTasks]）不刪，僅隱藏入口。
  /// 實際是否顯示請用 [dailyCareTasksVisible]。
  static const bool showDailyCareTasks = bool.fromEnvironment(
    'SHOW_DAILY_CARE_TASKS',
    defaultValue: true,
  );

  /// 今日任務入口實際是否顯示；正式功能已完成時依 build flag 控制。
  static bool get dailyCareTasksVisible => showDailyCareTasks;

  static const String defaultSttProxyUrl = '$backendBaseUrl/api/stt/transcribe';
  static const String realtimeSessionUrl =
      '$backendBaseUrl/api/realtime/session';
  static const String realtimeCallUrl = '$backendBaseUrl/api/realtime/call';
  static const String appUsageEventsUrl =
      '$backendBaseUrl/api/app-usage/events';
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
