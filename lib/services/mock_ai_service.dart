class MockAiService {
  String replyForChat(
    String userText,
    String petName, {
    String memoryContextSummary = '',
  }) {
    final memoryReply =
        _replyFromMemory(userText, petName, memoryContextSummary);
    if (memoryReply.isNotEmpty) return memoryReply;

    if (userText.contains('孤單') ||
        userText.contains('無聊') ||
        userText.contains('沒人陪') ||
        userText.contains('攏無人')) {
      return userText.contains('今仔日') || userText.contains('攏無人')
          ? '今仔日感覺有點安靜齁，我在這裡陪你，咱慢慢講幾句就好。'
          : '我在這裡陪你喔，今天是不是有點安靜？我們可以一起聊聊天。';
    }
    if (userText.contains('難過') ||
        userText.contains('想哭') ||
        userText.contains('累')) {
      return '聽起來今天有點辛苦，$petName 會陪你慢慢說，不用急。';
    }
    if (userText.contains('緊張') ||
        userText.contains('擔心') ||
        userText.contains('害怕')) {
      return '先陪你深呼吸一下，我們一步一步來，$petName 在你旁邊。';
    }
    if (userText.contains('開心') ||
        userText.contains('很好') ||
        userText.contains('快樂')) {
      return '太好了，聽到你這樣說，$petName 也覺得很開心。';
    }
    if (userText.contains('謝謝')) {
      return '不客氣，我是 $petName，會一直陪著你。';
    }
    return '$petName 在這裡陪你，我們慢慢來就好。';
  }

  String _replyFromMemory(
    String userText,
    String petName,
    String memoryContextSummary,
  ) {
    if (memoryContextSummary.isEmpty) return '';
    final context = memoryContextSummary;
    if ((userText.contains('睡眠') ||
            userText.contains('睡不好') ||
            userText.contains('健康小知識')) &&
        (context.contains('睡') || context.contains('精神'))) {
      return '你之前有提到最近晚上比較睡不好，我們可以先從放鬆作息開始。睡前把燈光調暗、少滑手機，讓身體慢慢知道該休息了。';
    }
    if (userText.contains('故事') &&
        (context.contains('台灣地方故事') || context.contains('地方故事'))) {
      return '我記得你喜歡台灣地方故事，那我等等可以說一個有土地味道的小故事給你聽。$petName 會用慢慢的語氣陪你聽。';
    }
    return '';
  }
}
