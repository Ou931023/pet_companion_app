import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pet_companion_app/widgets/pet_subtitle_text.dart';

void main() {
  group('PetSubtitleText.paginate (CR-0080)', () {
    const maxChars = 28;

    test('短回覆只有一頁、內容完整保留', () {
      const text = '我在這裡陪你。';
      final pages = PetSubtitleText.paginateForTest(text);
      expect(pages.length, 1);
      expect(pages.first, text);
    });

    test('空字串不產生任何頁', () {
      expect(PetSubtitleText.paginateForTest('   '), isEmpty);
    });

    test('長回覆會分成多頁，且每頁不超過上限', () {
      final text = List.filled(
        6,
        '我在這裡陪你慢慢說，先不用急著一次講完。',
      ).join();
      final pages = PetSubtitleText.paginateForTest(text);
      expect(pages.length, greaterThan(1));
      for (final page in pages) {
        expect(page.runes.length, lessThanOrEqualTo(maxChars), reason: page);
      }
    });

    test('分頁不漏字：所有頁去標點後可重組回原字元序列', () {
      final text = List.filled(
        5,
        '今天天氣不錯，出門記得帶水，慢慢走比較舒服。',
      ).join();
      final pages = PetSubtitleText.paginateForTest(text);
      final rejoined = pages.join().replaceAll(RegExp(r'\s'), '');
      final original = text.replaceAll(RegExp(r'\s'), '');
      expect(rejoined, original);
    });

    test('無標點的超長句也會被硬切，不會出現爆量單頁', () {
      final text = '陪' * 100; // 無任何標點
      final pages = PetSubtitleText.paginateForTest(text);
      expect(pages.length, greaterThan(1));
      for (final page in pages) {
        expect(page.runes.length, lessThanOrEqualTo(maxChars));
      }
    });
  });

  testWidgets('單頁回覆不會留下待處理的計時器', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PetSubtitleText(
            text: '我在這裡陪你。',
            textStyle: TextStyle(fontSize: 18),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('我在這裡陪你。'), findsOneWidget);
    // 無多頁 → 不排計時器；測試結束不應有 pending timer。
  });
}
