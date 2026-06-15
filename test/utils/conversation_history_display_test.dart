import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/models/conversation_session_summary.dart';
import 'package:pet_companion_app/models/conversation_turn.dart';
import 'package:pet_companion_app/utils/conversation_history_display.dart';

// CR-0091：對話紀錄友善呈現 + 本地搜尋純邏輯測試。
void main() {
  ConversationSessionSummary session(
    String id,
    String title,
    String preview, {
    String emotion = 'neutral',
  }) =>
      ConversationSessionSummary(
        sessionId: id,
        title: title,
        updatedAt: DateTime(2026, 1, 1),
        lastPreview: preview,
        emotionTag: emotion,
      );

  ConversationTurn turn(String sid, String user, String pet) => ConversationTurn(
        timestamp: DateTime(2026, 1, 1),
        userText: user,
        petReply: pet,
        toolName: '',
        sessionId: sid,
      );

  group('friendlyMoodLabel：不外漏 raw key、neutral 不顯示', () {
    test('情緒轉成白話心情描述', () {
      expect(friendlyMoodLabel('sad'), '有點低落');
      expect(friendlyMoodLabel('happy'), '心情不錯');
      expect(friendlyMoodLabel('lonely'), '有點孤單');
      expect(friendlyMoodLabel('anxious'), '有些擔心');
      expect(friendlyMoodLabel('tired'), '比較累');
      expect(friendlyMoodLabel('angry'), '有些不開心');
    });

    test('neutral / 空 / 不認得 → null（不顯示，且不外漏原值）', () {
      expect(friendlyMoodLabel('neutral'), isNull);
      expect(friendlyMoodLabel(''), isNull);
      expect(friendlyMoodLabel(null), isNull);
      expect(friendlyMoodLabel('riskLevel'), isNull);
      expect(friendlyMoodLabel('petMood'), isNull);
    });

    test('回傳值絕不等於原始 enum key', () {
      for (final tag in ['sad', 'happy', 'tired', 'anxious']) {
        expect(friendlyMoodLabel(tag), isNot(tag));
      }
    });
  });

  group('filterConversationSessions：本地搜尋', () {
    final sessions = [
      session('a', '聊到散步', '今天去散步'),
      session('b', '吃藥提醒', '記得吃藥'),
      session('c', '台語閒聊', '今仔日足累'),
    ];
    final turns = [
      turn('a', '我今天去散步', '散步對身體很好'),
      turn('b', '等一下提醒我吃藥', '好，我會提醒你'),
      turn('c', '我今仔日足累', '慢慢來，有我佇遮陪你'),
    ];

    List<String> ids(String q) => filterConversationSessions(
          sessions: sessions,
          allTurns: turns,
          query: q,
        ).map((s) => s.sessionId).toList();

    test('空查詢 → 回全部（原順序）', () {
      expect(ids(''), ['a', 'b', 'c']);
      expect(ids('   '), ['a', 'b', 'c']);
    });

    test('搜尋長者說的話（中文）', () {
      expect(ids('散步'), ['a']);
    });

    test('搜尋寵物回覆', () {
      expect(ids('我會提醒你'), ['b']);
    });

    test('搜尋標題 / 預覽', () {
      expect(ids('吃藥'), ['b']);
    });

    test('搜尋台語文字（漢字）', () {
      expect(ids('足累'), ['c']);
      expect(ids('佇遮'), ['c']);
    });

    test('大小寫不敏感（英文）', () {
      final s = [session('x', 'Hello Pet', 'hi')];
      final t = [turn('x', 'HELLO there', 'Hi')];
      final out = filterConversationSessions(sessions: s, allTurns: t, query: 'hello');
      expect(out.map((e) => e.sessionId), ['x']);
    });

    test('沒有符合 → 空清單', () {
      expect(ids('不存在的字'), isEmpty);
    });
  });
}
