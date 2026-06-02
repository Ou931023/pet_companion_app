// CR-0025 日常照護任務模型。
//
// **與既有遊戲化 `CareTask`（金幣/親密度）完全不同**，刻意用 DailyCareTask 命名
// 隔離：長者完成吃藥 / 喝水 / 運動任務後拍照上傳，後端 AI Vision 確認後更新狀態。

/// 任務類型（吃藥 / 喝水 / 運動）。
enum DailyCareTaskType { medication, hydration, exercise }

/// 任務狀態機（對齊後端 store）。
enum DailyCareTaskStatus {
  pending,
  submitted,
  completed,
  needsReview,
  rejected,
  missed,
}

/// AI 影像驗證狀態。
enum DailyCareVerificationStatus { passed, uncertain, failed }

DailyCareTaskType dailyCareTaskTypeFromString(String? raw) {
  switch ((raw ?? '').trim().toLowerCase()) {
    case 'hydration':
      return DailyCareTaskType.hydration;
    case 'exercise':
    case 'walk':
      return DailyCareTaskType.exercise;
    case 'medication':
    default:
      return DailyCareTaskType.medication;
  }
}

String dailyCareTaskTypeToString(DailyCareTaskType type) {
  switch (type) {
    case DailyCareTaskType.medication:
      return 'medication';
    case DailyCareTaskType.hydration:
      return 'hydration';
    case DailyCareTaskType.exercise:
      return 'exercise';
  }
}

/// 任務類型的長者友善中文標籤。
String dailyCareTaskTypeLabel(DailyCareTaskType type) {
  switch (type) {
    case DailyCareTaskType.medication:
      return '吃藥';
    case DailyCareTaskType.hydration:
      return '喝水';
    case DailyCareTaskType.exercise:
      return '運動';
  }
}

DailyCareTaskStatus dailyCareTaskStatusFromString(String? raw) {
  switch ((raw ?? '').trim().toLowerCase()) {
    case 'submitted':
      return DailyCareTaskStatus.submitted;
    case 'completed':
      return DailyCareTaskStatus.completed;
    case 'needs_review':
      return DailyCareTaskStatus.needsReview;
    case 'rejected':
      return DailyCareTaskStatus.rejected;
    case 'missed':
      return DailyCareTaskStatus.missed;
    case 'pending':
    default:
      return DailyCareTaskStatus.pending;
  }
}

/// 任務狀態的長者友善中文文案（見 CR SECTION 06A）。
String dailyCareTaskStatusLabel(DailyCareTaskStatus status) {
  switch (status) {
    case DailyCareTaskStatus.pending:
      return '待完成';
    case DailyCareTaskStatus.submitted:
      return '已送出';
    case DailyCareTaskStatus.completed:
      return '已完成';
    case DailyCareTaskStatus.needsReview:
      return '等待照護人員查看';
    case DailyCareTaskStatus.rejected:
      return '未通過';
    case DailyCareTaskStatus.missed:
      return '已逾時';
  }
}

DailyCareVerificationStatus dailyCareVerificationStatusFromString(String? raw) {
  switch ((raw ?? '').trim().toLowerCase()) {
    case 'passed':
      return DailyCareVerificationStatus.passed;
    case 'failed':
      return DailyCareVerificationStatus.failed;
    case 'uncertain':
    default:
      return DailyCareVerificationStatus.uncertain;
  }
}

/// AI 影像驗證結果。
class DailyCareTaskVerification {
  const DailyCareTaskVerification({
    required this.status,
    required this.confidence,
    required this.reason,
    required this.detectedObjects,
    required this.reviewRequired,
  });

  final DailyCareVerificationStatus status;
  final double confidence;
  final String reason;
  final List<String> detectedObjects;
  final bool reviewRequired;

  factory DailyCareTaskVerification.fromJson(Map<String, dynamic> json) {
    final rawConfidence = json['confidence'];
    final confidence = rawConfidence is num ? rawConfidence.toDouble() : 0.0;
    return DailyCareTaskVerification(
      status: dailyCareVerificationStatusFromString(
        json['verificationStatus'] as String?,
      ),
      confidence: confidence,
      reason: json['reason'] as String? ?? '',
      detectedObjects: (json['detectedObjects'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      reviewRequired: json['reviewRequired'] == true,
    );
  }

  /// 信心分數百分比顯示（管理者端用）。
  String get confidencePercentLabel =>
      '${(confidence * 100).clamp(0, 100).toStringAsFixed(0)}%';
}

/// 一筆完成證明 submission。
class DailyCareTaskSubmission {
  const DailyCareTaskSubmission({
    required this.id,
    required this.taskId,
    required this.status,
    required this.submittedAt,
    required this.verification,
    required this.note,
  });

  final String id;
  final String taskId;
  final DailyCareTaskStatus status;
  final String submittedAt;
  final DailyCareTaskVerification? verification;
  final String note;

  factory DailyCareTaskSubmission.fromJson(Map<String, dynamic> json) {
    final verificationJson = json['verification'];
    return DailyCareTaskSubmission(
      id: json['id'] as String? ?? '',
      taskId: json['taskId'] as String? ?? '',
      status: dailyCareTaskStatusFromString(json['status'] as String?),
      submittedAt: json['submittedAt'] as String? ?? '',
      verification: verificationJson is Map<String, dynamic>
          ? DailyCareTaskVerification.fromJson(verificationJson)
          : null,
      note: json['note'] as String? ?? '',
    );
  }
}

/// 日常照護任務。
class DailyCareTask {
  const DailyCareTask({
    required this.id,
    required this.elderId,
    required this.title,
    required this.type,
    required this.description,
    required this.scheduledTime,
    required this.status,
    required this.proofRequired,
    this.latestSubmission,
  });

  final String id;
  final String elderId;
  final String title;
  final DailyCareTaskType type;
  final String description;

  /// "HH:mm" 顯示用，可能為空字串。
  final String scheduledTime;
  final DailyCareTaskStatus status;
  final bool proofRequired;

  /// 管理者端列表會帶最新一筆 submission（長者端通常為 null）。
  final DailyCareTaskSubmission? latestSubmission;

  String get typeLabel => dailyCareTaskTypeLabel(type);
  String get statusLabel => dailyCareTaskStatusLabel(status);

  factory DailyCareTask.fromJson(Map<String, dynamic> json) {
    final latest = json['latestSubmission'];
    return DailyCareTask(
      id: json['id'] as String? ?? '',
      elderId: json['elderId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      type: dailyCareTaskTypeFromString(json['type'] as String?),
      description: json['description'] as String? ?? '',
      scheduledTime: json['scheduledTime'] as String? ?? '',
      status: dailyCareTaskStatusFromString(json['status'] as String?),
      proofRequired: json['proofRequired'] != false,
      latestSubmission: latest is Map<String, dynamic>
          ? DailyCareTaskSubmission.fromJson(latest)
          : null,
    );
  }
}
