import '../controllers/profile_controller.dart';
import '../controllers/task_controller.dart';
import '../controllers/wallet_controller.dart';
import '../models/ai_tool_result.dart';
import '../models/pet_status.dart';
import '../services/mock_ai_service.dart';
import '../services/mock_shop_service.dart';
import 'companion_content_service.dart';
import '../services/web_search_service.dart';

class AiToolRouter {
  AiToolRouter({
    required this.profileController,
    required this.taskController,
    required this.walletController,
    required this.shopService,
    required this.webSearchService,
    required this.mockAiService,
    required this.companionContentService,
  });

  final ProfileController profileController;
  final TaskController taskController;
  final WalletController walletController;
  final MockShopService shopService;
  final WebSearchService webSearchService;
  final MockAiService mockAiService;
  final CompanionContentService companionContentService;

  Future<AiToolResult> route(
    String userText, {
    String memoryContextSummary = '',
  }) async {
    final normalized = userText.trim();
    if (_isDailyCheckIn(normalized)) {
      return _dailyCheckIn();
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

  bool _isDailyCheckIn(String text) =>
      text.contains('簽到') || text.contains('每日簽到') || text.contains('今天簽到了嗎');

  bool _isBuyRequest(String text) =>
      text.contains('買') || text.contains('購買') || text.contains('幫我買');

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
    if (taskController.isTaskCompleted('dailyCheckIn')) {
      return AiToolResult(
        toolName: 'dailyCheckIn',
        success: true,
        message: '今天已經完成簽到囉，${profileController.petName} 很開心看到你這麼自律！',
        petMode: PetMode.happy,
        shouldSpeak: true,
        updatedCoins: profileController.coins,
      );
    }
    await taskController.completeTaskById('dailyCheckIn');
    return AiToolResult(
      toolName: 'dailyCheckIn',
      success: true,
      message: '今天的每日簽到已經完成囉，金幣增加 10 枚，${profileController.petName} 覺得你很棒！',
      petMode: PetMode.excited,
      shouldSpeak: true,
      updatedCoins: profileController.coins,
    );
  }

  Future<AiToolResult> _buyShopItem(String text) async {
    final product = shopService.findByText(text);
    if (product == null) {
      return const AiToolResult(
        toolName: 'buyShopItem',
        success: false,
        message: '我目前找不到這個商品，你可以試試狗狗餅乾或營養補充飲。',
        petMode: PetMode.listening,
        shouldSpeak: true,
      );
    }
    final canBuy = await walletController.spendCoins(product.price);
    if (!canBuy) {
      return AiToolResult(
        toolName: 'buyShopItem',
        success: false,
        message: '你目前金幣不足，${product.name} 需要 ${product.price} 枚金幣。',
        petMode: PetMode.sad,
        shouldSpeak: true,
      );
    }
    return AiToolResult(
      toolName: 'buyShopItem',
      success: true,
      message:
          '已經幫你購買${product.name}囉，花費 ${product.price} 枚金幣，目前剩下 ${profileController.coins} 枚金幣。',
      petMode: PetMode.happy,
      shouldSpeak: true,
      updatedCoins: profileController.coins,
      extraData: {'product': product.name},
    );
  }

  AiToolResult _getUserStatus() {
    final checkedIn =
        taskController.isTaskCompleted('dailyCheckIn') ? '已簽到' : '尚未簽到';
    return AiToolResult(
      toolName: 'getUserStatus',
      success: true,
      message:
          '你目前有 ${profileController.coins} 枚金幣，${profileController.petName} 的親密度是 ${profileController.bond}，飽足度是 ${profileController.fullness}，心情值是 ${profileController.mood}。今天完成 ${taskController.completedCount} 個任務，$checkedIn。',
      petMode: PetMode.happy,
      shouldSpeak: true,
      updatedCoins: profileController.coins,
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
          '今天的任務有喝水、吃飯、心情回報和每日簽到。你目前已完成 ${done.isEmpty ? '尚無' : done.join('、')}，還有 ${pending.isEmpty ? '都完成了，太棒了！' : pending.join('、')} 可以完成。',
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
}
