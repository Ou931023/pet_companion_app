import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/utils/zh_convert.dart';

void main() {
  group('toTraditional', () {
    test('簡體高風險語句轉成繁體', () {
      expect(
        toTraditional('我最近常常一个人觉得活着好累，都睡不着也不想吃东西'),
        '我最近常常一個人覺得活著好累，都睡不著也不想吃東西',
      );
    });

    test('常見對話簡體字逐字轉繁體', () {
      expect(toTraditional('这样会让我觉得开心'), '這樣會讓我覺得開心');
      expect(toTraditional('时间过得真快'), '時間過得真快');
      expect(toTraditional('谢谢你陪我说话'), '謝謝你陪我說話');
    });

    test('本來就是繁體 / 英數 / 標點 原樣保留', () {
      const traditional = '今天天氣很好，謝謝你！OK 123';
      expect(toTraditional(traditional), traditional);
    });

    test('空字串安全', () {
      expect(toTraditional(''), '');
    });

    test('emoji 與未收錄字元不被破壞', () {
      expect(toTraditional('你好🐱'), '你好🐱');
    });
  });
}
