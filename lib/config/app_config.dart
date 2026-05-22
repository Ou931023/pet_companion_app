class AppConfig {
  static const String backendBaseUrl = String.fromEnvironment(
    'BACKEND_BASE_URL',
    defaultValue: 'http://127.0.0.1:3001',
  );
  static const String defaultSttProxyUrl = '$backendBaseUrl/api/stt/transcribe';
  static const String realtimeSessionUrl =
      '$backendBaseUrl/api/realtime/session';
  static const String realtimeCallUrl = '$backendBaseUrl/api/realtime/call';
  static const String careMallUrl = String.fromEnvironment(
    'CARE_MALL_URL',
    defaultValue: 'http://127.0.0.1:5500',
  );

  /// 是否顯示開發用面板（Realtime Diagnostics / Companion Debug Panel /
  /// AI Agent 工具測試）。預設 false，Demo build 保持隱藏；
  /// 開發時用 --dart-define=SHOW_DEV_PANELS=true 啟用。
  static const bool showDevPanels = bool.fromEnvironment('SHOW_DEV_PANELS');

  static const Set<String> legacyBackendHosts = {
    '127.0.0.1',
    'localhost',
    '10.0.2.2',
  };

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
