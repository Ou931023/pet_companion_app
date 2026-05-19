class AgentToolExecutionResult {
  const AgentToolExecutionResult({
    required this.success,
    required this.toolName,
    required this.message,
    this.data = const {},
  });

  final bool success;
  final String toolName;
  final String message;
  final Map<String, dynamic> data;

  factory AgentToolExecutionResult.succeeded({
    required String toolName,
    required String message,
    Map<String, dynamic> data = const {},
  }) {
    return AgentToolExecutionResult(
      success: true,
      toolName: toolName,
      message: message,
      data: data,
    );
  }

  factory AgentToolExecutionResult.failed({
    required String toolName,
    required String message,
    Map<String, dynamic> data = const {},
  }) {
    return AgentToolExecutionResult(
      success: false,
      toolName: toolName,
      message: message,
      data: data,
    );
  }
}
