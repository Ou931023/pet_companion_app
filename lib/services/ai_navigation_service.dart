import '../routes/app_routes.dart';

class AiNavigationIntent {
  const AiNavigationIntent({
    required this.route,
    required this.reply,
  });

  final String route;
  final String reply;
}

class AiNavigationService {
  const AiNavigationService();

  AiNavigationIntent? detect(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty) return null;

    if (_containsAny(normalized, const ['回首頁', '回到首頁', '帶我回首頁'])) {
      return const AiNavigationIntent(
        route: AppRoute.home,
        reply: '好，我帶你回首頁。',
      );
    }
    if (_containsAny(normalized, const ['我要改設定', '打開設定', '去設定', '設定一下'])) {
      return const AiNavigationIntent(
        route: AppRoute.settings,
        reply: '好，我帶你去設定。',
      );
    }
    if (_containsAny(normalized, const ['帶我去通知中心', '我要看通知', '打開通知', '通知中心'])) {
      return const AiNavigationIntent(
        route: AppRoute.notification,
        reply: '好，我帶你去通知中心。',
      );
    }
    if (_containsAny(
        normalized, const ['打開相簿', '我想看照片', '我要看照片', '看照片', '相簿'])) {
      return const AiNavigationIntent(
        route: AppRoute.album,
        reply: '好，我帶你去看照片。',
      );
    }

    return null;
  }

  bool _containsAny(String text, List<String> keywords) {
    return keywords.any(text.contains);
  }
}
