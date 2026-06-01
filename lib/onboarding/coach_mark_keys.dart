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

/// 取底部導覽列最右邊 1/4（= 4 格中的「設定」）。
Rect settingsRightQuarter(Rect raw) =>
    Rect.fromLTWH(raw.left + raw.width * 3 / 4, raw.top, raw.width / 4, raw.height);

/// 首頁新手導覽的步驟（寵物 → 語音 → 狀態 → 提醒 → 設定）。
List<CoachMarkStep> buildHomeCoachMarkSteps(CoachMarkKeys keys) {
  return [
    CoachMarkStep(
      targetKey: keys.petKey,
      text: '這是陪你的寵物。想一起玩的時候，輕輕點牠就能開始小遊戲。',
    ),
    CoachMarkStep(
      targetKey: keys.voiceButtonKey,
      text: '想說話就點這顆大按鈕，直接跟我聊天，不用打字。',
    ),
    CoachMarkStep(
      targetKey: keys.statusKey,
      text: '這裡看得到寵物的親密、飽足和心情，多陪牠就會更好喔。',
    ),
    CoachMarkStep(
      targetKey: keys.reminderKey,
      text: '點這個鬧鐘，可以設定吃藥、喝水的提醒，時間到我會提醒你。',
    ),
    CoachMarkStep(
      targetKey: keys.navBarKey,
      rectTransform: settingsRightQuarter,
      text: '畫面最下面這排，最右邊的「設定」可以調整字體大小、聲音，也能再看一次這份介紹。',
    ),
  ];
}
