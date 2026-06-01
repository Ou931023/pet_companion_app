import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/onboarding/coach_mark_keys.dart';

void main() {
  test('首頁新手導覽是單一完整導覽，共有 13 步', () {
    final steps = buildHomeCoachMarkSteps(CoachMarkKeys());
    expect(steps.length, 13);
  });

  test('navBarSlot 高亮框排除 bottom safe area、不往下多出一截（CR-0023）', () {
    // 整條底部列：高度 120 含 34 的 home indicator / safe area。
    const raw = Rect.fromLTWH(0, 700, 400, 120);
    final slot = navBarSlot(raw, 1, bottomInset: 34);
    // 寬度仍是 1/4 格、左緣對到該格、上緣對齊 tab。
    expect(slot.left, 100);
    expect(slot.width, 100);
    expect(slot.top, raw.top);
    // 高度排除 safe area（120-34=86），且明顯比整條列矮、不超出可視 tab。
    expect(slot.height, lessThan(raw.height));
    expect(slot.height, lessThanOrEqualTo(88));
    expect(slot.bottom, lessThan(raw.bottom));
  });

  test('navBarSlot 高度會被夾在合理上限（過高的列也只包 tab）', () {
    const raw = Rect.fromLTWH(0, 0, 400, 200);
    final slot = navBarSlot(raw, 3, bottomInset: 0);
    expect(slot.height, lessThanOrEqualTo(88));
  });

  test('每一步的文字都不重複（Step 內容不重複）', () {
    final steps = buildHomeCoachMarkSteps(CoachMarkKeys());
    final texts = steps.map((s) => s.text).toList();
    expect(texts.toSet().length, texts.length, reason: '步驟文字不應重複');
  });

  test('每一步都有白話說明文字，不留空字串', () {
    final steps = buildHomeCoachMarkSteps(CoachMarkKeys());
    for (final step in steps) {
      expect(step.text.trim(), isNotEmpty);
    }
  });

  test('導覽涵蓋 寵物 / 說話 / 狀態 / 親密度 / 飽足 / 金幣 / 商城 / 紀錄 / 設定 / 聯絡',
      () {
    final steps = buildHomeCoachMarkSteps(CoachMarkKeys());
    final joined = steps.map((s) => s.text).join('\n');
    for (final keyword in [
      '寵物',
      '說話',
      '狀態',
      '親密度',
      '飽足',
      '金幣',
      '商城',
      '記錄',
      '設定',
      '聯絡',
    ]) {
      expect(joined, contains(keyword), reason: '導覽應涵蓋「$keyword」');
    }
  });

  test('第一步指向寵物、最後一步指向設定頁聯絡人入口', () {
    final keys = CoachMarkKeys();
    final steps = buildHomeCoachMarkSteps(keys);
    expect(steps.first.targetKey, keys.petKey);
    expect(steps.last.targetKey, keys.settingsContactKey);
  });

  test('Step 8 高亮每日簽到 icon、Step 9 高亮金幣區（index 7 / 8）', () {
    final keys = CoachMarkKeys();
    final steps = buildHomeCoachMarkSteps(keys);
    expect(steps[7].targetKey, keys.dailyCheckInKey);
    expect(steps[8].targetKey, keys.coinKey);
  });

  test('Step 10 / 11 / 12 都高亮底部導覽列（商城 / 紀錄 / 設定，index 9~11）', () {
    final keys = CoachMarkKeys();
    final steps = buildHomeCoachMarkSteps(keys);
    for (final i in [9, 10, 11]) {
      expect(steps[i].targetKey, keys.navBarKey, reason: 'Step ${i + 1} 應高亮底部列');
      expect(steps[i].rectTransform, isNotNull, reason: 'Step ${i + 1} 應切出對應那一格');
    }
  });

  test('Step 13 跨頁切到設定頁（shellTabIndex=3）並高亮聯絡人入口', () {
    final keys = CoachMarkKeys();
    final steps = buildHomeCoachMarkSteps(keys);
    expect(steps[12].targetKey, keys.settingsContactKey);
    expect(steps[12].shellTabIndex, 3);
  });

  test('有 target 的步驟都指向已知的高亮 key（不會指到野生 key）', () {
    final keys = CoachMarkKeys();
    final steps = buildHomeCoachMarkSteps(keys);
    final known = {
      keys.petKey,
      keys.voiceButtonKey,
      keys.statusKey,
      keys.reminderKey,
      keys.navBarKey,
      keys.dailyCheckInKey,
      keys.coinKey,
      keys.settingsContactKey,
    };
    for (final step in steps) {
      if (step.targetKey != null) {
        expect(known, contains(step.targetKey));
      }
    }
  });

  test('只有「先聽牠說完」那步沒有 target → overlay 安全降級為置中卡片，不 crash', () {
    final steps = buildHomeCoachMarkSteps(CoachMarkKeys());
    final noTarget = steps.where((s) => s.targetKey == null).toList();
    expect(noTarget, hasLength(1));
    expect(noTarget.single.text, contains('先聽'));
  });

  test('文字白話、不出現工程 / debug 字樣', () {
    final steps = buildHomeCoachMarkSteps(CoachMarkKeys());
    final joined = steps.map((s) => s.text).join('\n');
    for (final banned in ['debug', 'Debug', 'test', 'TODO', 'null', 'error']) {
      expect(joined.contains(banned), isFalse, reason: '不應出現「$banned」');
    }
  });
}
