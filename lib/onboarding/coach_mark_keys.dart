import 'package:flutter/widgets.dart';

import 'coach_mark_controller.dart';

/// 共享的導覽高亮目標 key。
///
/// HomeScreen 掛上寵物 / 語音 / 狀態 / 提醒入口的 key；MainShell 掛上底部
/// 導覽列的 key。集中放在這裡，讓「組步驟」與「畫面」解耦，HomeScreen 不需要
/// 知道導覽流程邏輯。
class CoachMarkKeys {
  final GlobalKey petKey = GlobalKey(debugLabel: 'coach_pet');
  final GlobalKey voiceButtonKey = GlobalKey(debugLabel: 'coach_voice');
  final GlobalKey statusKey = GlobalKey(debugLabel: 'coach_status');
  final GlobalKey reminderKey = GlobalKey(debugLabel: 'coach_reminder');

  /// 底部導覽列（整條）的 key。設定是 4 格中最右邊那格，用 [settingsRightQuarter]
  /// 取右側 1/4 當高亮框。iOS 原生導覽列拿不到 Flutter 框時，該步驟會降級為置中說明。
  final GlobalKey navBarKey = GlobalKey(debugLabel: 'coach_nav_bar');
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
/// 每步只介紹一件事、文字白話溫柔。**有 target 的步驟**會在首頁高亮對應區塊
/// （寵物 / 語音鍵 / 狀態面板 / 底部分頁）；**沒有 target 的步驟**（先聽牠說完、
/// 每日簽到、金幣）目前在首頁沒有穩定可高亮的元件，overlay 會自動降級成
/// 「畫面變暗 + 文字置中」的卡片說明，避免硬做不穩定的跨頁高亮或 crash。
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
    // 8：每日簽到可以拿金幣（簽到在最上方，無穩定 key → 置中卡片）。
    const CoachMarkStep(
      text: '每天回來看看寵物，就能完成每日簽到，拿到金幣。',
    ),
    // 9：金幣可以用來解鎖外觀（概念說明 → 置中卡片）。
    const CoachMarkStep(
      text: '存下來的金幣，可以用來解鎖新的寵物外觀。',
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
      text: '旁邊的「紀錄」可以回顧以前的心情、提醒和互動。',
    ),
    // 12：設定可以改寵物名稱和語音方式（高亮底部「設定」分頁）。
    CoachMarkStep(
      targetKey: keys.navBarKey,
      rectTransform: settingsRightQuarter,
      text: '「設定」可以幫寵物改名字，也可以調整說話的語音方式。',
    ),
    // 13：設定可以新增聯絡人（仍在「設定」分頁，最後一步）。
    CoachMarkStep(
      targetKey: keys.navBarKey,
      rectTransform: settingsRightQuarter,
      text: '在「設定」裡還能新增家人或照護人員，需要時更方便聯絡。',
    ),
  ];
}
