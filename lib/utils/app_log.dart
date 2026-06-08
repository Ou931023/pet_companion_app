import 'package:flutter/foundation.dart';

/// 共用 log helper。
///
/// 設計原則（CR-0047）：
/// - 正式版（`kReleaseMode`）預設「不輸出」，避免在 App Store / Play 正式 build
///   洩漏 token、完整逐字稿、完整 Care Alert 摘要等個資與機敏資訊。
///   （注意：Flutter 的 `debugPrint` 在 release 仍會輸出，所以高風險 log
///    必須改走這個 helper 或用 `kDebugMode` 包住。）
/// - debug / profile build 才會輸出，方便開發追蹤。
/// - 提供遮蔽 token、截斷逐字稿、遮蔽 Care Alert 摘要等工具方法，
///   讓「就算在 debug 也只留必要摘要」成為慣例。
///
/// 這個 helper「只負責 log 輸出」，不改變任何狀態機 / 錯誤處理語意。
/// 呼叫端的 try/catch、狀態追蹤與回傳值都不受影響。
class AppLog {
  AppLog._();

  /// 一般除錯訊息。release build 下為 no-op。
  static void debug(String message) {
    if (kReleaseMode) return;
    debugPrint(message);
  }

  /// 錯誤訊息。release build 下為 no-op。
  ///
  /// 這只是「不輸出錯誤細節」，呼叫端的錯誤處理（rethrow / fallback /
  /// 回傳值）完全不受影響，不會吞錯。
  static void error(String message, [Object? error]) {
    if (kReleaseMode) return;
    if (error == null) {
      debugPrint(message);
      return;
    }
    debugPrint('$message: ${error.runtimeType}');
  }

  /// 截斷逐字稿，避免輸出完整對話內容。
  ///
  /// 即使在 debug build 也只保留前幾個字 + 長度，方便辨識但不外洩完整內容。
  static String previewTranscript(String? transcript, {int maxChars = 8}) {
    if (transcript == null) return '(null)';
    final trimmed = transcript.trim();
    if (trimmed.isEmpty) return '(empty)';
    final runes = trimmed.runes.toList();
    if (runes.length <= maxChars) {
      return '${runes.length}字';
    }
    final head = String.fromCharCodes(runes.take(maxChars));
    return '$head…(${runes.length}字)';
  }

  /// 遮蔽 token / 權杖，只保留頭尾少量字元供辨識，永遠不輸出完整值。
  static String redactToken(String? token) {
    if (token == null || token.isEmpty) return '(none)';
    if (token.length <= 8) return '***';
    return '${token.substring(0, 4)}…${token.substring(token.length - 4)}';
  }

  /// 遮蔽 Care Alert 摘要 / 逐字片段，只保留長度資訊。
  static String redactSummary(String? summary) {
    if (summary == null) return '(null)';
    final trimmed = summary.trim();
    if (trimmed.isEmpty) return '(empty)';
    return '${trimmed.runes.length}字摘要';
  }
}
