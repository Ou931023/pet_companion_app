import '../routes/app_routes.dart';

/// CR-0101：導航後額外動作。
enum NavigationAction { none, replayOnboarding }

class AiNavigationIntent {
  const AiNavigationIntent({
    required this.route,
    required this.reply,
    this.action = NavigationAction.none,
    this.arguments,
  });

  final String route;
  final String reply;
  final NavigationAction action;
  final Object? arguments;
}

class AiNavigationService {
  const AiNavigationService();

  AiNavigationIntent? detect(String text) {
    final normalized = _toTraditional(text.trim());
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
    final dailyCareTaskArgs = _dailyCareTaskArgs(normalized);
    if (dailyCareTaskArgs != null) {
      return AiNavigationIntent(
        route: AppRoute.dailyCareTasks,
        reply:
            '好，我帶你去今日任務，請按「${dailyCareTaskArgs.requestedTaskLabel ?? '任務'}」的拍照完成，再拍一張照片。',
        arguments: dailyCareTaskArgs,
      );
    }
    if (_containsAny(
        normalized, const ['打開相簿', '我想看照片', '我要看照片', '看照片', '相簿'])) {
      return const AiNavigationIntent(
        route: AppRoute.album,
        reply: '好，我帶你去看照片。',
      );
    }

    // CR-0101：更換寵物造型 → 設定頁。
    if (_containsAny(normalized, const ['我要換造型', '幫寵物換外觀', '換寵物', '換造型'])) {
      return const AiNavigationIntent(
        route: AppRoute.settings,
        reply: '好，我帶你去更換寵物造型。',
      );
    }

    // CR-0101：今日關心紀錄。
    if (_containsAny(normalized, const ['我要看關心紀錄', '今天有什麼關心紀錄', '關心紀錄'])) {
      return const AiNavigationIntent(
        route: AppRoute.careAlerts,
        reply: '好，我帶你去看今天的關心紀錄。',
      );
    }

    // CR-0101：重新觀看新手導覽 → 首頁 + 觸發 replay。
    if (_containsAny(normalized, const ['重新教我一次', '再看一次新手導覽', '重新看導覽'])) {
      return const AiNavigationIntent(
        route: AppRoute.home,
        reply: '好，我帶你重新看一次新手導覽。',
        action: NavigationAction.replayOnboarding,
      );
    }

    return null;
  }

  bool _containsAny(String text, List<String> keywords) {
    return keywords.any(text.contains);
  }

  static const Map<String, String> _s2tMap = {
    '药': '藥',
    '设': '設',
    '关': '關',
    '开': '開',
    '页': '頁',
    '首': '首',
    '导': '導',
    '览': '覽',
    '护': '護',
    '务': '務',
    '认': '認',
    '传': '傳',
    '过': '過',
    '经': '經',
    '运': '運',
    '动': '動',
    '写': '寫',
    '儿': '兒',
  };

  static String _toTraditional(String input) {
    final buffer = StringBuffer();
    for (final ch in input.split('')) {
      buffer.write(_s2tMap[ch] ?? ch);
    }
    return buffer.toString();
  }

  DailyCareTaskRouteArgs? _dailyCareTaskArgs(String text) {
    if (_containsAny(text, const [
      '今日任務',
      '照護任務',
      '打開任務',
      '去任務',
    ])) {
      return const DailyCareTaskRouteArgs(launchedFromVoice: true);
    }
    if (_containsAny(text, const [
      '我要拍照',
      '拍照確認',
      '照片確認',
      '上傳照片',
    ])) {
      return DailyCareTaskRouteArgs(
        launchedFromVoice: true,
        requestedTaskType: _taskTypeFromText(text),
        requestedTaskLabel: _taskLabelFromText(text),
      );
    }
    if (_containsAny(text, const [
      '我吃藥了',
      '藥吃了',
      '吃過藥了',
      '已經吃藥',
    ])) {
      return const DailyCareTaskRouteArgs(
        launchedFromVoice: true,
        requestedTaskType: 'medication',
        requestedTaskLabel: '吃藥',
      );
    }
    if (_containsAny(text, const [
      '我喝水了',
      '水喝了',
      '已經喝水',
    ])) {
      return const DailyCareTaskRouteArgs(
        launchedFromVoice: true,
        requestedTaskType: 'hydration',
        requestedTaskLabel: '喝水',
      );
    }
    if (_containsAny(text, const [
      '我運動了',
      '我散步了',
      '散步回來',
      '走路回來',
    ])) {
      return const DailyCareTaskRouteArgs(
        launchedFromVoice: true,
        requestedTaskType: 'exercise',
        requestedTaskLabel: '運動',
      );
    }
    return null;
  }

  String? _taskTypeFromText(String text) {
    if (text.contains('藥')) return 'medication';
    if (text.contains('水')) return 'hydration';
    if (text.contains('運動') || text.contains('散步') || text.contains('走路')) {
      return 'exercise';
    }
    return null;
  }

  String? _taskLabelFromText(String text) {
    if (text.contains('藥')) return '吃藥';
    if (text.contains('水')) return '喝水';
    if (text.contains('運動') || text.contains('散步') || text.contains('走路')) {
      return '運動';
    }
    return null;
  }
}
