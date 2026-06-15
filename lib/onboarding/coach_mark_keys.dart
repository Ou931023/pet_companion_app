import 'package:flutter/widgets.dart';

import 'coach_mark_controller.dart';

/// 共享的導覽高亮目標 key。
///
/// HomeScreen 掛上寵物 / 語音 / 狀態 / 提醒 / 簽到 / 金幣的 key；MainShell 掛上
/// 底部導覽列（整條）的 key；SettingsScreen 掛上「家人聯絡人」入口的 key。
/// 集中放在這裡，讓「組步驟」與「畫面」解耦，畫面端只需把 key 掛上去，不需要
/// 知道導覽流程邏輯。命名沿用專案既有風格（單一 registry，不另開第二套）。
class CoachMarkKeys {
  // 首頁主要區塊。
  final GlobalKey petKey = GlobalKey(debugLabel: 'coach_pet');
  final GlobalKey voiceButtonKey = GlobalKey(debugLabel: 'coach_voice');
  final GlobalKey statusKey = GlobalKey(debugLabel: 'coach_status');
  final GlobalKey reminderKey = GlobalKey(debugLabel: 'coach_reminder');

  // 首頁頂部列：每日簽到 / 日曆 icon、金幣區（CR-0016 v2 新增，讓 Step 8 / 9 有真 target）。
  final GlobalKey dailyCheckInKey = GlobalKey(debugLabel: 'coach_daily_checkin');
  final GlobalKey coinKey = GlobalKey(debugLabel: 'coach_coin');

  /// 底部導覽列（整條）的 key。掛在 MainShell 底部列的外層 KeyedSubtree 上，
  /// 不論是 Flutter [NavigationBar] 或 iOS 原生列（UiKitView），都能取得這條列的
  /// 螢幕框，再用 [navBarSlot] 切出商城 / 紀錄 / 設定那一格高亮（CR-0016 v2：
  /// 解決原生列拿不到框、底部 tab 不會亮的實機問題）。
  final GlobalKey navBarKey = GlobalKey(debugLabel: 'coach_nav_bar');

  /// 設定頁「家人聯絡人」入口的 key（跨頁高亮用）。
  final GlobalKey settingsContactKey =
      GlobalKey(debugLabel: 'coach_settings_contact');

  // CR-0092：跨頁導覽真正切到該頁並高亮頁內目標（不再只亮底部分頁按鈕）。
  /// 商城頁頂部（切到商城分頁時高亮）。
  final GlobalKey shopKey = GlobalKey(debugLabel: 'coach_shop');

  /// 紀錄頁標題（切到紀錄分頁時高亮）。
  final GlobalKey historyTitleKey = GlobalKey(debugLabel: 'coach_history_title');

  /// 紀錄頁搜尋框（CR-0091）；無紀錄時搜尋框不顯示 → overlay 自動降級置中卡。
  final GlobalKey historySearchKey =
      GlobalKey(debugLabel: 'coach_history_search');

  /// 設定頁「換一隻陪你的夥伴 / 更換外觀」入口（切到設定分頁時高亮）。
  final GlobalKey settingsAppearanceKey =
      GlobalKey(debugLabel: 'coach_settings_appearance');

  /// 設定頁「重新觀看新手導覽」入口。
  final GlobalKey settingsReplayKey =
      GlobalKey(debugLabel: 'coach_settings_replay');
}

/// 取底部導覽列第 [index] 格（共 [total] 格）的高亮框。
///
/// 首頁底部 4 格：0 首頁、1 商城、2 紀錄、3 設定。用來把「商城 / 紀錄 / 設定」
/// 那幾步的高亮框，對準該功能的分頁按鈕。
/// 取底部導覽列第 [index] 格的高亮框。
///
/// CR-0023：整條底部列的框（[raw]）高度包含 iOS home indicator / bottom safe area，
/// 直接用會讓高亮框往下多出一大截、沒對齊 tab。這裡把 [bottomInset]（safe area）扣掉，
/// 並把高度夾在合理範圍（大約只包住 icon + label + 背景 capsule），上緣對齊 tab。
Rect navBarSlot(Rect raw, int index, {int total = 4, double bottomInset = 0}) {
  final usable = (raw.height - bottomInset).clamp(0.0, 88.0);
  return Rect.fromLTWH(
    raw.left + raw.width * index / total,
    raw.top,
    raw.width / total,
    usable,
  );
}

/// 取底部導覽列最右邊 1/4（= 4 格中的「設定」）。
Rect settingsRightQuarter(Rect raw, {double bottomInset = 0}) =>
    navBarSlot(raw, 3, bottomInset: bottomInset);

/// 首頁新手導覽的步驟，共 **16 步**（單一完整導覽，CR-0092 改為「實際帶走一遍」跨頁）：
///
/// 首頁：1 寵物 → 2 說話 → 3 先聽牠說完 → 4 狀態 → 5 親密度 → 6 飽足感 →
/// 7 點寵物玩遊戲 → 8 每日簽到 → 9 金幣 →
/// 商城頁：10 商城 →
/// 紀錄頁：11 紀錄 → 12 搜尋紀錄 →
/// 設定頁：13 換造型 → 14 家人聯絡人 → 15 重看導覽 →
/// 回首頁：16 開始使用。
///
/// 每步只介紹一件事、文字白話溫柔，並高亮畫面上對應位置：
/// - 首頁可見元件（寵物 / 語音鍵 / 狀態面板 / 簽到 / 金幣）直接 spotlight。
/// - CR-0092：商城 / 紀錄 / 設定步驟帶 `shellTabIndex`，先切到該分頁再高亮頁內目標
///   （不再只亮底部分頁按鈕）；最後一步切回首頁。切頁由 CoachMarkHost 處理，
///   overlay 會等該頁目標 render 好再高亮。
/// - 第 3 步是行為提示（先聽牠說完），無對應元件 → 置中說明卡。
/// - 第 12 步搜尋框在「尚無紀錄」時不顯示 → 安全降級置中卡。
/// 任何 target 取不到時（還沒繪製 / 跨頁未就緒 / 該元件隱藏）都會安全降級成置中卡片，不 crash。
List<CoachMarkStep> buildHomeCoachMarkSteps(
  CoachMarkKeys keys, {
  double bottomNavInset = 0,
}) {
  return [
    // 1：這是你的 AI 寵物。
    CoachMarkStep(
      targetKey: keys.petKey,
      text: '這是你的 AI 寵物，牠會陪你聊天，也會慢慢記得你喜歡什麼。',
    ),
    // 2：按住這裡可以說話。
    CoachMarkStep(
      targetKey: keys.voiceButtonKey,
      text: '想說話就按這裡，聊天、提醒、說說心情，都可以直接講。',
    ),
    // 3：先聽寵物說完（行為提示，無對應元件 → 置中卡片）。
    const CoachMarkStep(
      text: '寵物在說話時，先聽牠說完，再換你說，這樣聊起來更順。',
    ),
    // 4：看看寵物狀態。
    CoachMarkStep(
      targetKey: keys.statusKey,
      text: '這裡可以看寵物的狀態，包含心情、飽足和親密度。',
    ),
    // 5：聊天可以增加親密度（仍指著狀態面板，文字換成親密度）。
    CoachMarkStep(
      targetKey: keys.statusKey,
      text: '常常和寵物聊天，牠會越來越熟悉你，這裡的親密度也會慢慢增加。',
    ),
    // 6：餵食可以提升飽足感。
    CoachMarkStep(
      targetKey: keys.statusKey,
      text: '寵物餓的時候可以餵牠，餵食能提升這裡的飽足感，讓牠保持好心情。',
    ),
    // 7：點擊寵物可以進入遊戲。
    CoachMarkStep(
      targetKey: keys.petKey,
      text: '輕輕點一下寵物，可以玩記憶小遊戲，動動腦也很有趣。',
    ),
    // 8：每日簽到可以拿金幣 → 高亮頂部日曆 / 簽到 icon。
    CoachMarkStep(
      targetKey: keys.dailyCheckInKey,
      radius: 14,
      text: '每天回來看看寵物，就能完成每日簽到，拿到金幣。',
    ),
    // 9：金幣可以用來解鎖外觀 → 高亮頂部金幣區。
    CoachMarkStep(
      targetKey: keys.coinKey,
      radius: 14,
      text: '上面這些金幣，可以用來解鎖新的寵物外觀。',
    ),
    // 10：CR-0092 切到「商城」分頁，高亮商城頁本身（不再只亮底部按鈕）。
    CoachMarkStep(
      targetKey: keys.shopKey,
      shellTabIndex: 1,
      text: '這是「商城」，可以用金幣幫寵物解鎖外觀或買點東西。',
    ),
    // 11：切到「紀錄」分頁，高亮紀錄頁標題。
    CoachMarkStep(
      targetKey: keys.historyTitleKey,
      shellTabIndex: 2,
      text: '這是「紀錄」，可以回顧你和寵物聊過的話。',
    ),
    // 12：仍在紀錄頁，高亮搜尋框（CR-0091）。無紀錄時搜尋框未顯示 → 安全降級置中卡。
    CoachMarkStep(
      targetKey: keys.historySearchKey,
      shellTabIndex: 2,
      text: '想找以前聊過的內容，可以在這裡搜尋。',
    ),
    // 13：切到「設定」分頁，高亮「換一隻夥伴 / 更換外觀」。
    CoachMarkStep(
      targetKey: keys.settingsAppearanceKey,
      shellTabIndex: 3,
      text: '在「設定」可以幫寵物換造型，狗狗、狐狸、雪貂、麻吉都能挑。',
    ),
    // 14：仍在設定頁，高亮「家人聯絡人」入口（沿用既有）。
    CoachMarkStep(
      targetKey: keys.settingsContactKey,
      shellTabIndex: 3,
      radius: 14,
      text: '在「設定」裡還能新增家人或照護人員，需要時更方便聯絡。',
    ),
    // 15：仍在設定頁，高亮「重新觀看新手導覽」，告訴長者之後可重看。
    CoachMarkStep(
      targetKey: keys.settingsReplayKey,
      shellTabIndex: 3,
      text: '以後想再看一次導覽，從這裡就能重新看一遍。',
    ),
    // 16：切回首頁，高亮寵物，結束導覽。
    CoachMarkStep(
      targetKey: keys.petKey,
      shellTabIndex: 0,
      text: '好了！現在就回到寵物身邊，開始陪牠聊聊天吧。',
    ),
  ];
}
