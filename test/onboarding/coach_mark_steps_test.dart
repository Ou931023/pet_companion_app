import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/onboarding/coach_mark_keys.dart';

void main() {
  test('首頁新手導覽是單一完整導覽，共有 13 步', () {
    final steps = buildHomeCoachMarkSteps(CoachMarkKeys());
    expect(steps.length, 13);
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
      '紀錄',
      '設定',
      '聯絡',
    ]) {
      expect(joined, contains(keyword), reason: '導覽應涵蓋「$keyword」');
    }
  });

  test('第一步指向寵物、最後一步指向底部導覽列（設定）', () {
    final keys = CoachMarkKeys();
    final steps = buildHomeCoachMarkSteps(keys);
    expect(steps.first.targetKey, keys.petKey);
    expect(steps.last.targetKey, keys.navBarKey);
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
    };
    for (final step in steps) {
      if (step.targetKey != null) {
        expect(known, contains(step.targetKey));
      }
    }
  });

  test('有些步驟沒有 target → overlay 會安全降級為置中卡片，不應 crash', () {
    final steps = buildHomeCoachMarkSteps(CoachMarkKeys());
    // 後段功能（先聽牠說完 / 簽到 / 金幣）首頁沒有穩定可高亮元件，
    // 改用置中卡片說明，因此一定存在 targetKey 為 null 的步驟。
    expect(steps.any((s) => s.targetKey == null), isTrue);
  });

  test('文字白話、不出現工程 / debug 字樣', () {
    final steps = buildHomeCoachMarkSteps(CoachMarkKeys());
    final joined = steps.map((s) => s.text).join('\n');
    for (final banned in ['debug', 'Debug', 'test', 'TODO', 'null', 'error']) {
      expect(joined.contains(banned), isFalse, reason: '不應出現「$banned」');
    }
  });
}
