class MockWebSearchService {
  String search(String query) {
    if (query.contains('嘉義') || query.contains('天氣')) {
      return '我幫你查了一下，今天嘉義天氣偏熱，出門記得補充水分，也可以帶一把傘比較安心。';
    }
    return '我先幫你做了即時資訊查詢，目前建議保持室內通風與規律補水。';
  }
}
