import '../controllers/check_in_controller.dart';
import '../controllers/inventory_controller.dart';
import '../controllers/pet_stats_controller.dart';
import '../controllers/profile_controller.dart';
import '../controllers/task_controller.dart';
import '../controllers/wallet_controller.dart';
import '../models/ai_tool_result.dart';
import '../models/pet_status.dart';
import 'companion_content_service.dart';
import 'mock_ai_service.dart';
import 'shop_service.dart';
import 'web_search_service.dart';

class AiToolRouter {
  AiToolRouter({
    required this.profileController,
    required this.taskController,
    required this.walletController,
    required this.checkInController,
    required this.petStatsController,
    required this.inventoryController,
    required this.shopService,
    required this.webSearchService,
    required this.mockAiService,
    required this.companionContentService,
  });

  final ProfileController profileController;
  final TaskController taskController;
  final WalletController walletController;
  final CheckInController checkInController;
  final PetStatsController petStatsController;
  final InventoryController inventoryController;
  final ShopService shopService;
  final WebSearchService webSearchService;
  final MockAiService mockAiService;
  final CompanionContentService companionContentService;

  Future<AiToolResult> route(
    String userText, {
    String memoryContextSummary = '',
  }) async {
    final normalized = _toTraditional(userText.trim());
    if (_isDailyCheckIn(normalized)) {
      return _dailyCheckIn();
    }
    if (_isSettingsRequest(normalized)) {
      return _changeSettings(normalized);
    }
    if (_isBuyRequest(normalized)) {
      return _buyShopItem(normalized);
    }
    if (_isGetStatus(normalized)) {
      return _getUserStatus();
    }
    if (_isGetTasks(normalized)) {
      return _getDailyTasks();
    }
    if (companionContentService.shouldHandle(normalized)) {
      return _companionContent(normalized);
    }
    if (WebSearchService.shouldSearch(normalized)) {
      return _webSearch(normalized);
    }
    if (_isCompleteTask(normalized)) {
      return _completeCareTask(normalized);
    }
    return _chat(normalized, memoryContextSummary: memoryContextSummary);
  }

  bool shouldHandleLocally(String text) {
    final normalized = _toTraditional(text.trim());
    return _isDailyCheckIn(normalized) ||
        _isBuyRequest(normalized) ||
        _isSettingsRequest(normalized) ||
        _isGetStatus(normalized) ||
        _isGetTasks(normalized) ||
        _isCompleteTask(normalized) ||
        companionContentService.shouldHandle(normalized) ||
        WebSearchService.shouldSearch(normalized);
  }

  // OpenAI transcribe sometimes returns Simplified Chinese for Taiwanese
  // users; normalize the chars used by our intent matchers so detection works
  // regardless of script. This is a targeted map, not a full S→T converter.
  static const Map<String, String> _s2tMap = {
    '签': '簽', '帮': '幫', '买': '買', '购': '購', '场': '場', '声': '聲',
    '乐': '樂', '设': '設', '记': '記', '欢': '歡', '务': '務', '历': '歷',
    '览': '覽', '号': '號', '医': '醫', '体': '體',
    '关': '關', '开': '開', '点': '點', '钟': '鐘', '币': '幣', '宠': '寵',
    '态': '態', '说': '說', '话': '話', '让': '讓', '听': '聽', '问': '問',
    '现': '現', '钱': '錢', '钢': '鋼', '银': '銀', '门': '門', '区': '區',
    '动': '動', '运': '運', '总': '總', '远': '遠', '过': '過', '应': '應',
    '处': '處', '会': '會', '后': '後', '从': '從', '们': '們', '为': '為',
    '东': '東', '车': '車', '电': '電', '简': '簡',
  };

  static String _toTraditional(String input) {
    final buffer = StringBuffer();
    for (final ch in input.split('')) {
      buffer.write(_s2tMap[ch] ?? ch);
    }
    return buffer.toString();
  }

  bool _isDailyCheckIn(String text) {
    if (text.contains('簽到') ||
        text.contains('每日簽到') ||
        text.contains('今天簽到了嗎')) {
      return true;
    }
    // Tolerate common transcription mishearings of 「簽到」 from gpt realtime
    // (e.g. 停到/添到/籤到/簽道/添道/簽倒/僉到) when the user clearly intended
    // a check-in.
    final phoneticMisreads = ['停到', '添到', '添道', '籤到', '簽道', '簽倒', '僉到', '前到'];
    return phoneticMisreads.any(text.contains);
  }

  bool _isBuyRequest(String text) {
    if (text.contains('不要買') || text.contains('不買')) return false;
    return text.contains('買') || text.contains('購買') || text.contains('幫我買');
  }

  bool _isSettingsRequest(String text) {
    if (text.contains('設定') ||
        text.contains('喜歡聽') ||
        text.contains('不要聽') ||
        text.contains('不想聽')) {
      return true;
    }
    final hasSettingAction = [
      '調',
      '改',
      '開',
      '關',
      '打開',
      '關掉',
      '放大',
      '降低',
      '提高',
      '不要',
      '靜音',
    ].any(text.contains);
    final hasSettingSubject = [
      '聲音',
      '出聲',
      '音量',
      '文字',
      '字體',
      '說話方式',
    ].any(text.contains);
    final hasSpeechStyle = [
      '慢慢說',
      '說慢',
      '慢一點',
      '溫柔',
      '有精神',
      '活潑',
    ].any(text.contains);
    return (hasSettingSubject && hasSettingAction) ||
        (hasSpeechStyle &&
            (hasSettingAction || text.contains('說話') || text.contains('方式')));
  }

  bool _isGetStatus(String text) =>
      text.contains('多少金幣') ||
      text.contains('金幣餘額') ||
      text.contains('寵物狀態') ||
      text.contains('寵物數值') ||
      text.contains('${profileController.petName} 狀態');

  bool _isGetTasks(String text) =>
      text.contains('今天有什麼任務') ||
      text.contains('每日任務') ||
      text.contains('任務清單') ||
      text.contains('還有什麼任務');

  bool _isCompleteTask(String text) =>
      text.contains('我喝水了') ||
      text.contains('我吃飯了') ||
      text.contains('我休息了') ||
      text.contains('我完成任務');

  Future<AiToolResult> _dailyCheckIn() async {
    if (checkInController.hasCheckedInToday) {
      await taskController.completeTaskById(
        'dailyCheckIn',
        grantReward: false,
      );
      return AiToolResult(
        toolName: 'dailyCheckIn',
        success: true,
        message: '今天已經完成簽到囉，${profileController.petName} 很開心看到你這麼自律！',
        petMode: PetMode.happy,
        shouldSpeak: true,
        updatedCoins: walletController.coins,
      );
    }

    final checkedIn = await checkInController.checkIn(
      walletController: walletController,
      petStatsController: petStatsController,
    );
    await taskController.completeTaskById(
      'dailyCheckIn',
      grantReward: false,
    );
    if (!checkedIn) {
      return AiToolResult(
        toolName: 'dailyCheckIn',
        success: true,
        message: '今天已經簽到過了，金幣目前有 ${walletController.coins} 枚。',
        petMode: PetMode.happy,
        shouldSpeak: true,
        updatedCoins: walletController.coins,
      );
    }
    return AiToolResult(
      toolName: 'dailyCheckIn',
      success: true,
      message:
          '今天的每日簽到已經完成囉，金幣增加 10 枚，目前有 ${walletController.coins} 枚，${profileController.petName} 覺得你很棒！',
      petMode: PetMode.excited,
      shouldSpeak: true,
      updatedCoins: walletController.coins,
    );
  }

  Future<AiToolResult> _buyShopItem(String text) async {
    final item = shopService.findByText(text);
    if (item == null) {
      final names = shopService.allItems().map((item) => item.name).join('、');
      return AiToolResult(
        toolName: 'buyShopItem',
        success: false,
        message: '我目前找不到這個商品。你可以請我買：$names。',
        petMode: PetMode.listening,
        shouldSpeak: true,
      );
    }
    if (item.onlyWhenDead && !petStatsController.isDead) {
      return AiToolResult(
        toolName: 'buyShopItem',
        success: false,
        message: '${item.name}現在還用不到，我先幫你省下金幣。',
        petMode: PetMode.caring,
        shouldSpeak: true,
      );
    }
    final canBuy = await walletController.spendCoins(item.price);
    if (!canBuy) {
      return AiToolResult(
        toolName: 'buyShopItem',
        success: false,
        message:
            '你目前金幣不足，${item.name} 需要 ${item.price} 枚金幣，你現在有 ${walletController.coins} 枚。',
        petMode: PetMode.sad,
        shouldSpeak: true,
      );
    }
    await inventoryController.addFromShop(item);
    return AiToolResult(
      toolName: 'buyShopItem',
      success: true,
      message:
          '已經幫你購買${item.name}囉，花費 ${item.price} 枚金幣，已放進背包，目前剩下 ${walletController.coins} 枚金幣。',
      petMode: PetMode.happy,
      shouldSpeak: true,
      updatedCoins: walletController.coins,
      extraData: {'itemId': item.id, 'itemName': item.name},
    );
  }

  Future<AiToolResult> _changeSettings(String text) async {
    if (text.contains('設定') &&
        !text.contains('聲音') &&
        !text.contains('音量') &&
        !text.contains('文字') &&
        !text.contains('字體') &&
        !text.contains('說話') &&
        !text.contains('喜歡聽') &&
        !text.contains('不要聽') &&
        !text.contains('不想聽')) {
      return const AiToolResult(
        toolName: 'changeSettings',
        success: true,
        message: '可以呀，你可以說「把聲音關掉」、「音量調小」、「文字調大」或「說話慢一點」。',
        petMode: PetMode.listening,
        shouldSpeak: true,
      );
    }

    if (_requestsTtsOff(text)) {
      await profileController.setTtsEnabled(false);
      return const AiToolResult(
        toolName: 'changeSettings',
        success: true,
        message: '好，我先把寵物說話聲音關掉。',
        petMode: PetMode.happy,
        shouldSpeak: false,
      );
    }
    if (_requestsTtsOn(text)) {
      await profileController.setTtsEnabled(true);
      return const AiToolResult(
        toolName: 'changeSettings',
        success: true,
        message: '好，我把寵物說話聲音打開了。',
        petMode: PetMode.happy,
        shouldSpeak: true,
      );
    }

    final volume = _volumeFromText(text);
    if (volume != null) {
      await profileController.setPetVolume(volume);
      final percent = (profileController.petVolume * 100).round();
      return AiToolResult(
        toolName: 'changeSettings',
        success: true,
        message: '好，音量已經調到 $percent%。',
        petMode: PetMode.happy,
        shouldSpeak: profileController.ttsEnabled,
      );
    }

    final fontScale = _fontScaleFromText(text);
    if (fontScale != null) {
      await profileController.setFontScale(fontScale);
      return AiToolResult(
        toolName: 'changeSettings',
        success: true,
        message: '好，文字大小已經調成${_fontScaleLabel(profileController.fontScale)}。',
        petMode: PetMode.happy,
        shouldSpeak: true,
      );
    }

    final speechStyle = _speechStyleFromText(text);
    if (speechStyle != null) {
      await profileController.setSpeechStyle(speechStyle);
      return AiToolResult(
        toolName: 'changeSettings',
        success: true,
        message:
            '好，我之後會用${_speechStyleLabel(profileController.speechStyle)}的方式陪你說話。',
        petMode: PetMode.happy,
        shouldSpeak: true,
      );
    }

    final preference = _contentPreferenceFromText(text);
    if (preference != null) {
      final enabled = !text.contains('不要') && !text.contains('不想');
      await profileController.setContentPreference(preference.key, enabled);
      return AiToolResult(
        toolName: 'changeSettings',
        success: true,
        message: enabled
            ? '好，我記住你${preference.label}。'
            : '好，我先不主動安排${preference.label}。',
        petMode: PetMode.happy,
        shouldSpeak: true,
      );
    }

    return const AiToolResult(
      toolName: 'changeSettings',
      success: false,
      message: '這個設定我還不太確定怎麼調，你可以試試「聲音關掉」、「音量調大」或「文字調大」。',
      petMode: PetMode.listening,
      shouldSpeak: true,
    );
  }

  AiToolResult _getUserStatus() {
    final checkedIn = checkInController.hasCheckedInToday ? '已簽到' : '尚未簽到';
    return AiToolResult(
      toolName: 'getUserStatus',
      success: true,
      message:
          '你目前有 ${walletController.coins} 枚金幣，${profileController.petName} 的親密度是 ${profileController.bond}，飽足度是 ${profileController.fullness}，心情值是 ${profileController.mood}。今天完成 ${taskController.completedCount} 個任務，$checkedIn。背包裡有 ${inventoryController.totalQuantity} 件物品。',
      petMode: PetMode.happy,
      shouldSpeak: true,
      updatedCoins: walletController.coins,
    );
  }

  AiToolResult _getDailyTasks() {
    final done = taskController.tasks
        .where((task) => task.completed)
        .map((task) => task.title);
    final pending = taskController.tasks
        .where((task) => !task.completed)
        .map((task) => task.title);
    return AiToolResult(
      toolName: 'getDailyTasks',
      success: true,
      message:
          '今天的任務有喝水、吃飯、心情回報、休息提醒和每日簽到。你目前已完成 ${done.isEmpty ? '尚無' : done.join('、')}，還有 ${pending.isEmpty ? '都完成了，太棒了！' : pending.join('、')} 可以完成。',
      petMode: PetMode.listening,
      shouldSpeak: true,
    );
  }

  Future<AiToolResult> _webSearch(String text) async {
    final result = await webSearchService.search(text);
    if (!result.success) {
      return AiToolResult(
        toolName: 'webSearch',
        success: false,
        message: result.message,
        petMode: PetMode.caring,
        shouldSpeak: true,
      );
    }
    return AiToolResult(
      toolName: 'webSearch',
      success: true,
      message: result.answer.isEmpty ? '我查到的資料不多，晚點再幫你確認一次。' : result.answer,
      petMode: PetMode.caring,
      shouldSpeak: true,
      extraData: {'highRisk': result.highRisk},
    );
  }

  bool isCompanionContentOrSearch(String text) {
    final normalized = text.trim();
    return companionContentService.shouldHandle(normalized) ||
        WebSearchService.shouldSearch(normalized);
  }

  Future<AiToolResult> _companionContent(String text) async {
    final result = await companionContentService.createContent(
      userText: text,
      preferences: profileController.contentPreferences,
    );
    return AiToolResult(
      toolName: 'companionContent',
      success: true,
      message: result.message,
      petMode: result.highRisk ? PetMode.caring : PetMode.happy,
      shouldSpeak: true,
      extraData: {
        'contentType': result.type.name,
        'usedWebSearch': result.usedWebSearch,
      },
    );
  }

  Future<AiToolResult> _completeCareTask(String text) async {
    String taskId = 'moodReport';
    if (text.contains('喝水')) taskId = 'drinkWater';
    if (text.contains('吃飯')) taskId = 'eatMeal';
    if (text.contains('休息')) taskId = 'restReminder';
    final completed = await taskController.completeTaskById(taskId);
    if (!completed) {
      return AiToolResult(
        toolName: 'completeCareTask',
        success: true,
        message: '這個任務今天已經完成囉，${profileController.petName} 幫你記住了。',
        petMode: PetMode.happy,
        shouldSpeak: true,
      );
    }
    return AiToolResult(
      toolName: 'completeCareTask',
      success: true,
      message: '太好了，已幫你更新任務進度，金幣與親密度都增加了，${profileController.petName} 為你加油！',
      petMode: PetMode.excited,
      shouldSpeak: true,
    );
  }

  AiToolResult _chat(String text, {String memoryContextSummary = ''}) {
    var mode = PetMode.listening;
    if (text.contains('難過') ||
        text.contains('孤單') ||
        text.contains('不舒服') ||
        text.contains('累') ||
        text.contains('沒人陪')) {
      mode = PetMode.caring;
    } else if (text.contains('開心') ||
        text.contains('很好') ||
        text.contains('謝謝')) {
      mode = PetMode.happy;
    } else if (text.contains('想睡') || text.contains('好累')) {
      mode = PetMode.sleepy;
    }
    return AiToolResult(
      toolName: 'chat',
      success: true,
      message: mockAiService.replyForChat(
        text,
        profileController.petName,
        memoryContextSummary: memoryContextSummary,
      ),
      petMode: mode,
      shouldSpeak: true,
    );
  }

  bool _requestsTtsOff(String text) {
    return (text.contains('關') || text.contains('不要') || text.contains('靜音')) &&
        (text.contains('聲音') || text.contains('出聲') || text.contains('說話'));
  }

  bool _requestsTtsOn(String text) {
    return (text.contains('開') || text.contains('打開') || text.contains('恢復')) &&
        (text.contains('聲音') || text.contains('出聲') || text.contains('說話'));
  }

  double? _volumeFromText(String text) {
    if (!text.contains('音量') && !text.contains('聲音')) return null;
    final percentMatch = RegExp(r'(\d{1,3})\s*%?').firstMatch(text);
    if (percentMatch != null) {
      final value = int.tryParse(percentMatch.group(1)!);
      if (value != null) return (value.clamp(0, 100) / 100).toDouble();
    }
    if (text.contains('最大') || text.contains('很大')) return 1.0;
    if (text.contains('調大') || text.contains('大聲') || text.contains('提高')) {
      return (profileController.petVolume + 0.2).clamp(0.0, 1.0);
    }
    if (text.contains('最小') || text.contains('很小')) return 0.2;
    if (text.contains('調小') || text.contains('小聲') || text.contains('降低')) {
      return (profileController.petVolume - 0.2).clamp(0.0, 1.0);
    }
    return null;
  }

  double? _fontScaleFromText(String text) {
    if (!text.contains('文字') && !text.contains('字體')) return null;
    if (text.contains('最大') || text.contains('很大')) return 1.3;
    if (text.contains('調大') || text.contains('放大') || text.contains('大一點')) {
      return (profileController.fontScale + 0.1).clamp(0.9, 1.3);
    }
    if (text.contains('較小') || text.contains('調小') || text.contains('小一點')) {
      return (profileController.fontScale - 0.1).clamp(0.9, 1.3);
    }
    if (text.contains('標準') || text.contains('正常')) return 1.0;
    return null;
  }

  String? _speechStyleFromText(String text) {
    if (text.contains('慢慢說') || text.contains('說慢') || text.contains('慢一點')) {
      return 'calm';
    }
    if (text.contains('有精神') || text.contains('活潑')) return 'bright';
    if (text.contains('溫柔')) return 'gentle';
    return null;
  }

  ({String key, String label})? _contentPreferenceFromText(String text) {
    if (!text.contains('喜歡聽') &&
        !text.contains('不要聽') &&
        !text.contains('不想聽')) {
      return null;
    }
    if (text.contains('故事')) return (key: 'story', label: '喜歡聽故事');
    if (text.contains('新聞')) return (key: 'news', label: '喜歡聽新聞');
    if (text.contains('健康')) return (key: 'healthTip', label: '喜歡健康提醒');
    if (text.contains('生活')) return (key: 'lifeTip', label: '喜歡生活小知識');
    if (text.contains('鼓勵') || text.contains('心靈')) {
      return (key: 'spiritual', label: '喜歡心靈鼓勵');
    }
    if (text.contains('懷舊')) return (key: 'nostalgicStory', label: '喜歡懷舊話題');
    return null;
  }

  String _fontScaleLabel(double value) {
    if (value >= 1.25) return '最大';
    if (value >= 1.1) return '較大';
    if (value < 1.0) return '較小';
    return '標準';
  }

  String _speechStyleLabel(String value) {
    return switch (value) {
      'bright' => '有精神',
      'calm' => '慢慢說',
      _ => '溫柔',
    };
  }
}
