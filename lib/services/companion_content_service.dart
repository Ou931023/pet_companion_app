import '../models/companion_content.dart';
import 'web_search_service.dart';

class CompanionContentService {
  CompanionContentService(this.webSearchService);

  final WebSearchService webSearchService;

  bool shouldHandle(String text) => detectType(text) != null;

  ContentType? detectType(String text) {
    final normalized = text.trim();
    if (normalized.contains('故事') || normalized.contains('陪我聊聊天')) {
      if (normalized.contains('以前') || normalized.contains('懷舊')) {
        return ContentType.nostalgicStory;
      }
      return ContentType.story;
    }
    if (normalized.contains('新聞')) return ContentType.news;
    if (normalized.contains('健康小知識') || normalized.contains('健康資訊')) {
      return ContentType.healthTip;
    }
    if (normalized.contains('詐騙')) return ContentType.scamAlert;
    if (normalized.contains('天氣')) return ContentType.weather;
    if (normalized.contains('生活小知識')) return ContentType.lifeTip;
    if (normalized.contains('鼓勵') || normalized.contains('心靈')) {
      return ContentType.spiritual;
    }
    return null;
  }

  Future<CompanionContentResult> createContent({
    required String userText,
    required List<String> preferences,
  }) async {
    final type = detectType(userText) ?? _typeFromPreference(preferences);
    if (_needsWeb(type)) {
      final query = _trustedQuery(userText, type);
      final result = await webSearchService.search(query);
      return CompanionContentResult(
        type: type,
        message: result.success && result.answer.isNotEmpty
            ? _petWrap(result.answer, type)
            : result.message,
        usedWebSearch: true,
        highRisk: result.highRisk || type == ContentType.healthTip,
      );
    }

    return CompanionContentResult(
      type: type,
      message: _localContent(type),
      usedWebSearch: false,
      highRisk: type == ContentType.healthTip,
    );
  }

  ContentType _typeFromPreference(List<String> preferences) {
    if (preferences.contains('nostalgicStory')) {
      return ContentType.nostalgicStory;
    }
    if (preferences.contains('news')) return ContentType.news;
    if (preferences.contains('healthTip')) return ContentType.healthTip;
    if (preferences.contains('spiritual')) return ContentType.spiritual;
    if (preferences.contains('lifeTip')) return ContentType.lifeTip;
    return ContentType.story;
  }

  bool _needsWeb(ContentType type) {
    return switch (type) {
      ContentType.news ||
      ContentType.healthTip ||
      ContentType.scamAlert ||
      ContentType.weather =>
        true,
      _ => false,
    };
  }

  String _trustedQuery(String userText, ContentType type) {
    final trustedHint = switch (type) {
      ContentType.healthTip => '政府 醫院 醫療機構 健康資訊',
      ContentType.scamAlert => '政府 警政 詐騙 防範 最新',
      ContentType.news => '主流新聞 官方公告 今日',
      ContentType.weather => '中央氣象署 天氣 今日',
      _ => '可信來源',
    };
    return '$userText $trustedHint';
  }

  String _petWrap(String answer, ContentType type) {
    final suffix =
        type == ContentType.healthTip ? ' 這只是一般資訊，如果身體不舒服，還是要詢問醫師或家人喔。' : '';
    return '我幫你整理一下：$answer$suffix';
  }

  String _localContent(ContentType type) {
    return switch (type) {
      ContentType.nostalgicStory =>
        '我講一個小故事給你聽。以前巷口常有賣麵茶的小攤，熱熱一碗捧在手裡，香氣慢慢散開。那時候日子簡單，可是有人一起坐著說話，就覺得心裡很暖。',
      ContentType.spiritual => '我陪你安靜一下。今天不需要急著把所有事做好，只要一步一步來，就已經很不容易了。',
      ContentType.lifeTip => '生活小提醒：喝水可以少量多次，不一定要一次喝很多。杯子放在看得到的地方，比較容易記得。',
      _ => '我講一個小故事給你聽。有一隻小寵物每天都陪在主人身邊，牠不會催人，只會輕輕提醒：今天也慢慢來，我都在。',
    };
  }
}
