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

  /// 設定頁「家人聯絡人」入口的 key（Step 13 跨頁高亮用）。
  final GlobalKey settingsContactKey =
      GlobalKey(debugLabel: 'coach_settings_contact');
}

/// 取底部導覽列第 [index] 格（共 [total] 格）的高亮框。
///
/// 首頁底部 4 格：0 首頁、1 商城、2 紀錄、3 設定。用來把「商城 / 紀錄 / 設定」
/// 那幾步的高亮框，對準該功能的分頁按鈕。
Rect navBarSlot(Rect raw, int index, {int total = 4}) => Rect.fromLTWH(
      raw.left + raw.width * index / total,
      raw.top,
      raw.width / total,
      raw.height,
    );

/// 取底部導覽列最右邊 1/4（= 4 格中的「設定」）。
Rect settingsRightQuarter(Rect raw) => navBarSlot(raw, 3);

/// 首頁新手導覽的步驟，共 **13 步**（單一完整導覽，不再分快速 / 完整版）：
///
/// 1 寵物 → 2 說話 → 3 先聽牠說完 → 4 狀態 → 5 親密度 → 6 飽足感 →
/// 7 點寵物玩遊戲 → 8 每日簽到 → 9 金幣 → 10 商城 → 11 紀錄 →
/// 12 設定改名 / 語音 → 13 設定新增聯絡人。
///
/// 每步只介紹一件事、文字白話溫柔，並盡量高亮畫面上對應的位置：
/// - 首頁可見元件（寵物 / 語音鍵 / 狀態面板 / 簽到 / 金幣）直接 spotlight。
/// - 商城 / 紀錄 / 設定高亮底部導覽列對應那一格。
/// - 第 13 步跨頁切到設定頁，高亮「家人聯絡人」入口。
/// - 第 3 步是行為提示（先聽牠說完），無對應元件 → overlay 自動降級成置中說明卡。
/// 任何 target 取不到時（還沒繪製 / 跨頁未就緒）都會安全降級成置中卡片，不 crash。
List<CoachMarkStep> buildHomeCoachMarkSteps(CoachMarkKeys keys) {
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
    // 10：商城可以購買或解鎖物品（高亮底部「商城」分頁）。
    CoachMarkStep(
      targetKey: keys.navBarKey,
      rectTransform: (raw) => navBarSlot(raw, 1),
      text: '最下面的「商城」可以用金幣解鎖外觀或其他物品。',
    ),
    // 11：記錄可以查看過去狀態（高亮底部「紀錄」分頁）。
    CoachMarkStep(
      targetKey: keys.navBarKey,
      rectTransform: (raw) => navBarSlot(raw, 2),
      text: '旁邊的「記錄」可以回顧以前的心情、提醒和互動。',
    ),
    // 12：設定可以改寵物名稱和語音方式（高亮底部「設定」分頁）。
    CoachMarkStep(
      targetKey: keys.navBarKey,
      rectTransform: settingsRightQuarter,
      text: '「設定」可以幫寵物改名字，也可以調整說話的語音方式。',
    ),
    // 13：設定可以新增聯絡人 → 跨頁切到設定頁、高亮「家人聯絡人」入口（最後一步）。
    CoachMarkStep(
      targetKey: keys.settingsContactKey,
      shellTabIndex: 3,
      radius: 14,
      text: '在「設定」裡還能新增家人或照護人員，需要時更方便聯絡。',
    ),
  ];
}
