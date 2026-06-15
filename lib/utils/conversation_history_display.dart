import '../models/conversation_session_summary.dart';
import '../models/conversation_turn.dart';

/// CR-0091：對話紀錄頁的長者友善呈現 + 本地搜尋（純函式，可單元測試）。
///
/// 原則：絕不把工程欄位（emotionTag / petMood / riskLevel 等 raw key）直接顯示給長者。

/// 把情緒 enum 轉成「簡短、白話、不醫療化」的心情描述。
/// neutral / 空 / 不認得 → 回 null（畫面就不顯示，保持乾淨、不雜亂）。
String? friendlyMoodLabel(String? emotionTag) {
  switch ((emotionTag ?? '').trim().toLowerCase()) {
    case 'happy':
      return '心情不錯';
    case 'sad':
      return '有點低落';
    case 'lonely':
      return '有點孤單';
    case 'anxious':
      return '有些擔心';
    case 'tired':
      return '比較累';
    case 'angry':
      return '有些不開心';
    default:
      // neutral / unknown / raw key 一律不顯示（不外漏 emotionTag 原值）。
      return null;
  }
}

/// 對話紀錄本地搜尋：依關鍵字過濾 session。
///
/// 比對範圍：session 標題、最後預覽，以及該 session 內每一則的「長者說的話」與
/// 「寵物回覆」。大小寫不敏感；中文與台語漢字皆為純文字 substring 比對。
/// [query] 去除前後空白後為空 → 回傳全部（維持原排序）。
List<ConversationSessionSummary> filterConversationSessions({
  required List<ConversationSessionSummary> sessions,
  required List<ConversationTurn> allTurns,
  required String query,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return sessions;

  // 先把每個 session 的對話文字（長者話 + 寵物回覆）串起來，避免每個 session 都重掃。
  final bodyBySession = <String, StringBuffer>{};
  for (final turn in allTurns) {
    final buf = bodyBySession.putIfAbsent(turn.sessionId, () => StringBuffer());
    buf.write(turn.userText);
    buf.write('\n');
    buf.write(turn.petReply);
    buf.write('\n');
  }

  bool matches(ConversationSessionSummary s) {
    if (s.title.toLowerCase().contains(q)) return true;
    if (s.lastPreview.toLowerCase().contains(q)) return true;
    final body = bodyBySession[s.sessionId];
    return body != null && body.toString().toLowerCase().contains(q);
  }

  return sessions.where(matches).toList();
}
