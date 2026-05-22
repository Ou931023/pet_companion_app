// 長照提醒（Care Alert）資料模型。
//
// 用來把對話中偵測到的長者異常狀況，記錄成一筆可供長照人員或家屬查看的提醒。
// 此批次只建立資料地基，尚未與對話偵測串接（hook 留待下一個小批次）。

/// 提醒風險等級。目前先支援三級，與後端 safety_guard 一致。
enum CareAlertRiskLevel {
  normal,
  attention,
  urgent;

  static CareAlertRiskLevel fromJson(Object? value) {
    return switch (value?.toString()) {
      'urgent' => CareAlertRiskLevel.urgent,
      'attention' => CareAlertRiskLevel.attention,
      _ => CareAlertRiskLevel.normal,
    };
  }

  String toJson() => name;

  /// 長者 / 家屬看得懂的中文標籤。
  String get label => switch (this) {
        CareAlertRiskLevel.urgent => '緊急',
        CareAlertRiskLevel.attention => '需注意',
        CareAlertRiskLevel.normal => '一般',
      };
}

/// 異常狀況分類。對應專題目標 4 列出的長者異常類型。
enum CareAlertCategory {
  sleep,
  appetite,
  dizziness,
  fall,
  loneliness,
  depressed,
  selfHarm,
  needHelp,
  other;

  static CareAlertCategory fromJson(Object? value) {
    return switch (value?.toString()) {
      'sleep' => CareAlertCategory.sleep,
      'appetite' => CareAlertCategory.appetite,
      'dizziness' => CareAlertCategory.dizziness,
      'fall' => CareAlertCategory.fall,
      'loneliness' => CareAlertCategory.loneliness,
      'depressed' => CareAlertCategory.depressed,
      'selfHarm' => CareAlertCategory.selfHarm,
      'needHelp' => CareAlertCategory.needHelp,
      _ => CareAlertCategory.other,
    };
  }

  String toJson() => name;

  /// 長者 / 家屬看得懂的中文標籤。
  String get label => switch (this) {
        CareAlertCategory.sleep => '睡眠狀況',
        CareAlertCategory.appetite => '飲食狀況',
        CareAlertCategory.dizziness => '頭暈不適',
        CareAlertCategory.fall => '跌倒',
        CareAlertCategory.loneliness => '孤單',
        CareAlertCategory.depressed => '情緒低落',
        CareAlertCategory.selfHarm => '輕生念頭',
        CareAlertCategory.needHelp => '需要協助',
        CareAlertCategory.other => '其他',
      };
}

class CareAlert {
  const CareAlert({
    required this.id,
    required this.createdAt,
    required this.riskLevel,
    required this.category,
    required this.triggerSummary,
    required this.transcriptSnippet,
    required this.source,
    required this.isRead,
  });

  /// 唯一識別碼。
  final String id;

  /// 建立時間。
  final DateTime createdAt;

  /// 風險等級。
  final CareAlertRiskLevel riskLevel;

  /// 異常狀況分類。
  final CareAlertCategory category;

  /// 這筆提醒的簡短摘要。
  final String triggerSummary;

  /// 觸發這筆提醒的對話片段（長者說的話）。
  final String transcriptSnippet;

  /// 來源標記，例如 companion_analysis、manual。
  final String source;

  /// 是否已被長照人員 / 家屬標記為已查看。
  final bool isRead;

  CareAlert copyWith({
    String? id,
    DateTime? createdAt,
    CareAlertRiskLevel? riskLevel,
    CareAlertCategory? category,
    String? triggerSummary,
    String? transcriptSnippet,
    String? source,
    bool? isRead,
  }) {
    return CareAlert(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      riskLevel: riskLevel ?? this.riskLevel,
      category: category ?? this.category,
      triggerSummary: triggerSummary ?? this.triggerSummary,
      transcriptSnippet: transcriptSnippet ?? this.transcriptSnippet,
      source: source ?? this.source,
      isRead: isRead ?? this.isRead,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'createdAt': createdAt.toIso8601String(),
      'riskLevel': riskLevel.toJson(),
      'category': category.toJson(),
      'triggerSummary': triggerSummary,
      'transcriptSnippet': transcriptSnippet,
      'source': source,
      'isRead': isRead,
    };
  }

  factory CareAlert.fromJson(Map<String, dynamic> json) {
    return CareAlert(
      id: json['id']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      riskLevel: CareAlertRiskLevel.fromJson(json['riskLevel']),
      category: CareAlertCategory.fromJson(json['category']),
      triggerSummary: json['triggerSummary']?.toString() ?? '',
      transcriptSnippet: json['transcriptSnippet']?.toString() ?? '',
      source: json['source']?.toString() ?? '',
      isRead: json['isRead'] == true,
    );
  }
}
