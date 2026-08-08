import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/services/web_search_service.dart';

void main() {
  group('WebSearchService.shouldSearch 即時資訊 intent (CR-0080)', () {
    test('天氣 / 明確新聞主題 / 活動 / 詐騙等 intent 仍會進搜尋', () {
      for (final query in const [
        '今天有什麼防詐新聞？',
        '今仔日有啥健康新聞？',
        '嘉義地方新聞予我聽',
        '幫我查天氣',
        '附近有什麼活動？',
        '最近詐騙新聞有哪些？',
        '查一下這個健康資訊',
      ]) {
        expect(WebSearchService.shouldSearch(query), isTrue, reason: query);
      }
    });

    test('擴充：補助 / 政策 / 價格 / 天氣變體會進搜尋而不再被當閒聊', () {
      for (final query in const [
        '今天嘉義天氣如何？',
        '最近有什麼長照補助？',
        '現在有什麼股市新聞？',
        '敬老津貼怎麼申請？',
        '今天油價多少？',
        '這個颱風會不會放假？',
        '健保的規定有改嗎？',
      ]) {
        expect(WebSearchService.shouldSearch(query), isTrue, reason: query);
      }
    });

    test('泛用新聞請求先追問偏好，不直接搜尋', () {
      for (final query in const [
        '今天有什麼新聞？',
        '今仔日有啥新聞？',
        '有啥物新聞？',
        '新聞予我聽',
        '現在有什麼重要新聞？',
      ]) {
        expect(WebSearchService.shouldSearch(query), isFalse, reason: query);
        expect(WebSearchService.isBroadNewsRequest(query), isTrue, reason: query);
      }
    });

    test('一般陪伴聊天不應被誤判成搜尋', () {
      for (final query in const [
        '我今天有點累',
        '陪我聊聊天',
        '我現在心情不太好',
        '最近都睡不好',
        '今天好想你',
      ]) {
        expect(WebSearchService.shouldSearch(query), isFalse, reason: query);
      }
    });

    test('空字串不觸發搜尋', () {
      expect(WebSearchService.shouldSearch(''), isFalse);
      expect(WebSearchService.shouldSearch('   '), isFalse);
    });
  });
}
