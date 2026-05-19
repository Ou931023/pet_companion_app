enum AgentToolRiskLevel {
  low,
  medium,
  high;

  static AgentToolRiskLevel fromJson(Object? value) {
    return switch (value?.toString()) {
      'high' => AgentToolRiskLevel.high,
      'medium' => AgentToolRiskLevel.medium,
      _ => AgentToolRiskLevel.low,
    };
  }

  String toJson() => name;
}

enum AgentToolStatus {
  pending,
  confirmed,
  executing,
  executed,
  cancelled,
  failed;

  static AgentToolStatus fromJson(Object? value) {
    return switch (value?.toString()) {
      'confirmed' => AgentToolStatus.confirmed,
      'executing' => AgentToolStatus.executing,
      'executed' => AgentToolStatus.executed,
      'cancelled' => AgentToolStatus.cancelled,
      'failed' => AgentToolStatus.failed,
      _ => AgentToolStatus.pending,
    };
  }

  String toJson() => name;
}

class AgentToolIntent {
  const AgentToolIntent({
    required this.id,
    required this.toolName,
    required this.displayName,
    required this.arguments,
    required this.requiresConfirmation,
    required this.riskLevel,
    required this.status,
    required this.userFacingMessage,
    required this.createdAt,
  });

  final String id;
  final String toolName;
  final String displayName;
  final Map<String, dynamic> arguments;
  final bool requiresConfirmation;
  final AgentToolRiskLevel riskLevel;
  final AgentToolStatus status;
  final String userFacingMessage;
  final DateTime createdAt;

  bool get isHighRisk => riskLevel == AgentToolRiskLevel.high;

  bool get isExecutable =>
      status == AgentToolStatus.pending || status == AgentToolStatus.confirmed;

  AgentToolIntent copyWith({
    String? id,
    String? toolName,
    String? displayName,
    Map<String, dynamic>? arguments,
    bool? requiresConfirmation,
    AgentToolRiskLevel? riskLevel,
    AgentToolStatus? status,
    String? userFacingMessage,
    DateTime? createdAt,
  }) {
    return AgentToolIntent(
      id: id ?? this.id,
      toolName: toolName ?? this.toolName,
      displayName: displayName ?? this.displayName,
      arguments: arguments ?? this.arguments,
      requiresConfirmation: requiresConfirmation ?? this.requiresConfirmation,
      riskLevel: riskLevel ?? this.riskLevel,
      status: status ?? this.status,
      userFacingMessage: userFacingMessage ?? this.userFacingMessage,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory AgentToolIntent.fromJson(Map<String, dynamic> json) {
    return AgentToolIntent(
      id: json['id']?.toString() ?? '',
      toolName: json['toolName']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
      arguments: Map<String, dynamic>.from((json['arguments'] as Map?) ?? {}),
      requiresConfirmation: json['requiresConfirmation'] == true,
      riskLevel: AgentToolRiskLevel.fromJson(json['riskLevel']),
      status: AgentToolStatus.fromJson(json['status']),
      userFacingMessage: json['userFacingMessage']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'toolName': toolName,
      'displayName': displayName,
      'arguments': arguments,
      'requiresConfirmation': requiresConfirmation,
      'riskLevel': riskLevel.toJson(),
      'status': status.toJson(),
      'userFacingMessage': userFacingMessage,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
