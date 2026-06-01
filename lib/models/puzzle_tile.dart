/// 一局照片拼圖的結果。供退化指標 / 管理者端分析使用（完成時間是否變長、
/// 錯誤拖曳是否增加、難度完成率是否下降）。目前先在前端記錄，之後可接到
/// 既有 game result store / 後端分析，不另開第二套。
class PuzzleResult {
  const PuzzleResult({
    required this.difficulty,
    required this.totalPieces,
    required this.elapsedSeconds,
    required this.moveAttempts,
    required this.correctDrops,
    required this.wrongDrops,
    required this.completed,
    required this.completedAt,
  });

  /// '3x3' 或 '4x4'。
  final String difficulty;

  /// 9 或 16。
  final int totalPieces;
  final int elapsedSeconds;
  final int moveAttempts;
  final int correctDrops;
  final int wrongDrops;
  final bool completed;
  final DateTime completedAt;

  Map<String, dynamic> toJson() => {
        'difficulty': difficulty,
        'totalPieces': totalPieces,
        'elapsedSeconds': elapsedSeconds,
        'moveAttempts': moveAttempts,
        'correctDrops': correctDrops,
        'wrongDrops': wrongDrops,
        'completed': completed,
        'completedAt': completedAt.toIso8601String(),
      };
}
