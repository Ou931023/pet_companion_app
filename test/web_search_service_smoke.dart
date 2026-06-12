import 'package:pet_companion_app/services/web_search_service.dart';

void main() {
  final searchQueries = [
    '今天有什麼新聞？',
    '幫我查天氣',
    '附近有什麼活動？',
    '最近詐騙新聞有哪些？',
    '查一下這個健康資訊',
    // CR-0080：擴充的即時資訊 intent。
    '今天嘉義天氣如何？',
    '最近有什麼長照補助？',
    '現在有什麼重要新聞？',
    '敬老津貼怎麼申請？',
  ];
  for (final query in searchQueries) {
    assert(WebSearchService.shouldSearch(query), 'Expected search: $query');
  }

  final chatQueries = [
    '我今天有點累',
    '陪我聊聊天',
    '我現在心情不太好',
    '最近都睡不好',
  ];
  for (final query in chatQueries) {
    assert(!WebSearchService.shouldSearch(query), 'Expected chat: $query');
  }
}
