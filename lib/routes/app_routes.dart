class AppRoute {
  const AppRoute._();

  static const String home = '/home';
  static const String shop = '/shop';
  static const String marketplace = '/marketplace';
  static const String history = '/history';
  static const String settings = '/settings';
  static const String reminders = '/reminders';
  static const String dailyCareTasks = '/daily-care-tasks';
  static const String memories = '/memories';
  static const String album = '/album';
  static const String notification = '/notification';
  static const String puzzle = '/puzzle';
  static const String conversationDetail = '/conversation-detail';
  static const String careAlerts = '/care-alerts';

  static const List<String> shellRoutes = [
    home,
    shop,
    history,
    settings,
  ];
}

class ConversationDetailArgs {
  const ConversationDetailArgs({
    required this.sessionId,
    required this.title,
  });

  final String sessionId;
  final String title;
}

class DailyCareTaskRouteArgs {
  const DailyCareTaskRouteArgs({
    required this.launchedFromVoice,
    this.requestedTaskType,
    this.requestedTaskLabel,
  });

  final bool launchedFromVoice;
  final String? requestedTaskType;
  final String? requestedTaskLabel;
}
