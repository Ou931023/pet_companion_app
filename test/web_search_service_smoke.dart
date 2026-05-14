import 'package:pet_companion_app/services/web_search_service.dart';

void main() {
  final searchQueries = [
    '今天有什麼新聞？',
    '幫我查天氣',
    '附近有什麼活動？',
    '最近詐騙新聞有哪些？',
    '查一下這個健康資訊',
  ];
  for (final query in searchQueries) {
    assert(WebSearchService.shouldSearch(query), 'Expected search: $query');
  }

  final chatQueries = [
    '我今天有點累',
    '陪我聊聊天',
  ];
  for (final query in chatQueries) {
    assert(!WebSearchService.shouldSearch(query), 'Expected chat: $query');
  }
}
