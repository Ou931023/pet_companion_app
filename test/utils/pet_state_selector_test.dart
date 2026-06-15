import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/models/pet_status.dart';
import 'package:pet_companion_app/utils/pet_state_selector.dart';

/// CR-0088：寵物顯示狀態選擇器純邏輯測試（涵蓋 Part B 狀態觸發要求）。
void main() {
  // 健康預設（不觸發 care state）：滿足度/心情/親密度皆高。
  PetMode sel({
    bool mic = false,
    bool speaking = false,
    PetMode? transient,
    int? satiety = 70,
    int? mood = 70,
    int? intimacy = 70,
  }) {
    return PetStateSelector.select(
      isMicCapturing: mic,
      isPetSpeaking: speaking,
      transientMode: transient,
      satiety: satiety,
      mood: mood,
      intimacy: intimacy,
    );
  }

  test('收音中 → listening（最高優先）', () {
    expect(sel(mic: true, speaking: true, transient: PetMode.happy, satiety: 5),
        PetMode.listening);
  });

  test('寵物語音播放中 → talking（次高，蓋過 transient / care）', () {
    expect(sel(speaking: true, transient: PetMode.happy, satiety: 5),
        PetMode.talking);
  });

  test('非收音非播放：短暫情緒優先於 care / rest', () {
    expect(sel(transient: PetMode.happy, satiety: 5), PetMode.happy);
    expect(sel(transient: PetMode.caring), PetMode.caring);
  });

  test('飽足度低 → hungry', () {
    expect(sel(satiety: 20), PetMode.hungry);
  });

  test('心情低 → sad', () {
    expect(sel(satiety: 70, mood: 20), PetMode.sad);
  });

  test('親密度低 → caring', () {
    expect(sel(satiety: 70, mood: 70, intimacy: 20), PetMode.caring);
  });

  test('CR-0094：閒置不再因時段變 sleepy（狀態正常 → rest）', () {
    // 不論幾點，只要沒在收音/播放/短暫情緒、且數值正常 → 一律 rest（不再深夜 sleepy）。
    expect(sel(), PetMode.rest);
  });

  test('CR-0094：sleepy 只由情緒 tired 的短暫情緒觸發（非時段）', () {
    expect(PetStateSelector.transientModeForEmotion('tired'), PetMode.sleepy);
    // care state 不會自己產生 sleepy。
    expect(PetStateSelector.careStateFor(satiety: 70, mood: 70, intimacy: 70),
        isNull);
  });

  test('care 內優先序：飽足度低蓋過心情低 / 親密度低', () {
    expect(sel(satiety: 10, mood: 10, intimacy: 10), PetMode.hungry);
  });

  test('無互動、狀態正常 → rest（待機輪播）', () {
    expect(sel(), PetMode.rest);
  });

  test('資料缺漏（null）不硬觸發 care，回 rest', () {
    expect(
      sel(satiety: null, mood: null, intimacy: null),
      PetMode.rest,
    );
  });

  test('listening / talking 不會在非收音非播放時卡住（回 care / rest）', () {
    // 模擬語音 session idle：mic=false、speaking=false → 不應是 listening/talking。
    final m = sel();
    expect(m, isNot(PetMode.listening));
    expect(m, isNot(PetMode.talking));
  });

  group('情緒標籤 → 短暫狀態 mapping', () {
    test('正向 / 低落對應', () {
      expect(PetStateSelector.transientModeForEmotion('happy'), PetMode.happy);
      expect(PetStateSelector.transientModeForEmotion('excited'), PetMode.excited);
      expect(PetStateSelector.transientModeForEmotion('sad'), PetMode.sad);
      expect(PetStateSelector.transientModeForEmotion('lonely'), PetMode.caring);
      expect(PetStateSelector.transientModeForEmotion('anxious'), PetMode.caring);
      expect(PetStateSelector.transientModeForEmotion('tired'), PetMode.sleepy);
      expect(PetStateSelector.transientModeForEmotion('angry'), PetMode.caring);
    });
    test('neutral / 未知 → null（不觸發）', () {
      expect(PetStateSelector.transientModeForEmotion('neutral'), isNull);
      expect(PetStateSelector.transientModeForEmotion(null), isNull);
      expect(PetStateSelector.transientModeForEmotion('???'), isNull);
    });
  });
}
