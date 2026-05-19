import 'agent_tool_intent.dart';

class AgentRouteResult {
  const AgentRouteResult({
    required this.hasToolIntent,
    this.assistantMessage = '',
    this.intent,
    this.errorMessage = '',
  });

  final bool hasToolIntent;
  final String assistantMessage;
  final AgentToolIntent? intent;
  final String errorMessage;

  factory AgentRouteResult.noIntent({String errorMessage = ''}) {
    return AgentRouteResult(
      hasToolIntent: false,
      errorMessage: errorMessage,
    );
  }

  factory AgentRouteResult.fromJson(Map<String, dynamic> json) {
    final intentJson = json['intent'];
    return AgentRouteResult(
      hasToolIntent: json['hasToolIntent'] == true,
      assistantMessage: json['assistantMessage']?.toString() ?? '',
      intent: intentJson is Map
          ? AgentToolIntent.fromJson(Map<String, dynamic>.from(intentJson))
          : null,
      errorMessage: json['error']?.toString() ?? '',
    );
  }
}
