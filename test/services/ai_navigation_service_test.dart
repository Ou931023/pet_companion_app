import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/routes/app_routes.dart';
import 'package:pet_companion_app/services/ai_navigation_service.dart';

void main() {
  group('AiNavigationService daily care tasks', () {
    test('吃藥或散步完成語句會帶到今日任務照片驗證流程', () {
      const service = AiNavigationService();

      final medication = service.detect('我吃藥了');
      final walk = service.detect('我散步回來了');

      expect(medication, isNotNull);
      expect(medication!.route, AppRoute.dailyCareTasks);
      expect(medication.reply, contains('拍一張照片'));
      expect(walk, isNotNull);
      expect(walk!.route, AppRoute.dailyCareTasks);
    });

    test('拍照確認語句優先進今日任務，不誤導到相簿', () {
      const service = AiNavigationService();

      final intent = service.detect('我要拍照確認吃藥');

      expect(intent, isNotNull);
      expect(intent!.route, AppRoute.dailyCareTasks);
      expect(intent.route, isNot(AppRoute.album));
    });

    test('簡體 transcript 也能辨識吃藥完成語句', () {
      const service = AiNavigationService();

      final intent = service.detect('我吃药了');

      expect(intent, isNotNull);
      expect(intent!.route, AppRoute.dailyCareTasks);
    });
  });

  group('AiNavigationService transcript normalization', () {
    test('簡體首頁指令仍會回首頁', () {
      const service = AiNavigationService();

      final intent = service.detect('回首页');

      expect(intent, isNotNull);
      expect(intent!.route, AppRoute.home);
    });
  });
}
