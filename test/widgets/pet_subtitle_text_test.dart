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

  testWidgets('串流中：文字增長不重設計時器，第一頁念完會接到第二頁', (tester) async {
    const part1 = '阿明早安，今天天氣晴朗，很適合出門走走。';
    const full = '阿明早安，今天天氣晴朗，很適合出門走走。記得帶水，傍晚去散步看夕陽。回家之後先休息一下，晚上早點睡，有我陪著你。';
    final pages = PetSubtitleText.paginateForTest(full);
    expect(pages.length, greaterThan(1), reason: '完整文字應分成多頁');

    Widget host(String text) => MaterialApp(
          home: Scaffold(
            body: PetSubtitleText(
              text: text,
              streaming: true,
              textStyle: const TextStyle(fontSize: 18),
            ),
          ),
        );

    // 串流第一段（短）：只有一頁，顯示它。
    await tester.pumpWidget(host(part1));
    await tester.pump();
    expect(find.textContaining('阿明早安'), findsOneWidget);

    // 文字長到完整：先穩定留在第一頁，不直接跳去結尾。
    await tester.pumpWidget(host(full));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(find.text(pages.first), findsOneWidget);
    expect(find.textContaining('有我陪著你'), findsNothing);

    // 第一頁依語速時間念完後，串流尚未結束也會接著顯示第二頁。
    await tester.pump(const Duration(seconds: 8));
    expect(find.text(pages[1]), findsOneWidget);
  });

  testWidgets('串流轉 final 後從第一頁開始，依序顯示中間與最後一頁 (CR-0107)', (tester) async {
    const full =
        '阿明早安，今天天氣晴朗，很適合出門走走。記得帶水，傍晚去散步看夕陽。回家之後先休息一下，喝杯溫水。晚上早點睡，有我陪著你。';
    final pages = PetSubtitleText.paginateForTest(full);
    expect(pages.length, greaterThanOrEqualTo(3));

    Widget host({required bool streaming}) => MaterialApp(
          home: Scaffold(
            body: PetSubtitleText(
              text: full,
              streaming: streaming,
              textStyle: const TextStyle(fontSize: 18),
            ),
          ),
        );

    await tester.pumpWidget(host(streaming: true));
    expect(find.text(pages.first), findsOneWidget);

    await tester.pumpWidget(host(streaming: false));
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.text(pages.first), findsOneWidget);

    await tester.pump(const Duration(seconds: 9));
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.text(pages[1]), findsOneWidget);

    for (var index = 1; index < pages.length; index++) {
      await tester.pump(const Duration(seconds: 9));
      await tester.pump(const Duration(milliseconds: 220));
    }
    expect(find.text(pages.last), findsOneWidget);
  });

  testWidgets('串流已翻到第二頁時，final 接手不會跳回第一頁', (tester) async {
    const full =
        '阿明早安，今天天氣晴朗，很適合出門走走。記得帶水，傍晚去散步看夕陽。回家之後先休息一下，喝杯溫水。晚上早點睡，有我陪著你。';
    final pages = PetSubtitleText.paginateForTest(full);

    Widget host({required bool streaming}) => MaterialApp(
          home: Scaffold(
            body: PetSubtitleText(
              text: full,
              streaming: streaming,
              textStyle: const TextStyle(fontSize: 18),
            ),
          ),
        );

    await tester.pumpWidget(host(streaming: true));
    await tester.pump(const Duration(seconds: 8));
    expect(find.text(pages[1]), findsOneWidget);

    await tester.pumpWidget(host(streaming: false));
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.text(pages[1]), findsOneWidget);

    await tester.pump(const Duration(seconds: 90));
  });

  testWidgets('串流修正前文中的字時仍保留目前頁', (tester) async {
    const original = '阿明早安，今天天氣晴朗，很適合出門走走。記得帶水，傍晚去散步看夕陽。回家之後先休息一下，喝杯溫水。';
    const corrected = '阿美早安，今天天氣晴朗，很適合出門走走。記得帶水，傍晚去散步看夕陽。回家之後先休息一下，喝杯溫水。';
    final correctedPages = PetSubtitleText.paginateForTest(corrected);

    Widget host(String text) => MaterialApp(
          home: Scaffold(
            body: PetSubtitleText(
              text: text,
              streaming: true,
              textStyle: const TextStyle(fontSize: 18),
            ),
          ),
        );

    await tester.pumpWidget(host(original));
    await tester.pump(const Duration(seconds: 8));
    expect(find.text(PetSubtitleText.paginateForTest(original)[1]),
        findsOneWidget);

    await tester.pumpWidget(host(corrected));
    await tester.pump();
    expect(find.text(correctedPages[1]), findsOneWidget);

    await tester.pump(const Duration(seconds: 90));
  });

  testWidgets('箭頭可自由切換字幕頁，手動翻頁後本輪不再自動搶頁', (tester) async {
    const full =
        '阿明早安，今天天氣晴朗，很適合出門走走。記得帶水，傍晚去散步看夕陽。回家之後先休息一下，喝杯溫水。晚上早點睡，有我陪著你。';
    final pages = PetSubtitleText.paginateForTest(full);
    expect(pages.length, greaterThanOrEqualTo(3));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PetSubtitleText(
            text: full,
            textStyle: TextStyle(fontSize: 18),
          ),
        ),
      ),
    );

    expect(find.text('1 / ${pages.length}'), findsOneWidget);
    final previousAtStart = tester.widget<IconButton>(
      find.byKey(const ValueKey('pet-subtitle-previous-page')),
    );
    expect(previousAtStart.onPressed, isNull);

    await tester.tap(
      find.byKey(const ValueKey('pet-subtitle-next-page')),
    );
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.text(pages[1]), findsOneWidget);
    expect(find.text('2 / ${pages.length}'), findsOneWidget);

    // 手動選頁後，即使超過自動翻頁時間也停在使用者正在看的頁面。
    await tester.pump(const Duration(seconds: 30));
    expect(find.text(pages[1]), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('pet-subtitle-previous-page')),
    );
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.text(pages.first), findsOneWidget);
  });
}
