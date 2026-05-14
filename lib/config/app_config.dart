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

  static const Set<String> legacyBackendHosts = {
    '10.51.16.97',
  };

  static String realtimeCallUrlForSttProxy(String sttProxyUrl) {
    return _apiUrlFrom(sttProxyUrl, '/api/realtime/call');
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
    return uri.replace(path: apiPath, query: '', fragment: '').toString();
  }
}
