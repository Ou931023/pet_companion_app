import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/services/taigi_text_detection_service.dart';

void main() {
  group('TaigiTextDetectionService', () {
    const service = TaigiTextDetectionService();

    test('does not mark plain Mandarin as Taigi', () {
      final result = service.detect('今天心情不太好');

      expect(result.isLikelyTaigi, isFalse);
      expect(result.languageHint, 'zh');
    });

    test('detects mixed Taigi and Mandarin keywords', () {
      final result = service.detect('今仔日心情無好');

      expect(result.isLikelyTaigi, isTrue);
      expect(result.languageHint, 'taigi');
      expect(result.confidence, greaterThanOrEqualTo(0.8));
      expect(result.matchedKeywords, containsAll(['今仔日', '無好']));
      expect(result.reason, 'matched_taigi_mixed_zh_keywords');
    });

    test('detects elder colloquial Taigi phrase', () {
      final result = service.detect('食飽未，我今天有點無聊');

      expect(result.isLikelyTaigi, isTrue);
      expect(result.languageHint, 'taigi');
      expect(result.matchedKeywords, containsAll(['食飽未', '無聊']));
    });

    test('detects lonely Taigi context without changing emotion rules', () {
      final result = service.detect('今仔日家裡攏無人，我感覺足孤單');

      expect(result.isLikelyTaigi, isTrue);
      expect(result.matchedKeywords, containsAll(['今仔日', '攏', '足']));
    });

    test('does not over-detect everyday Mandarin shopping text', () {
      final result = service.detect('我今天想去買東西');

      expect(result.isLikelyTaigi, isFalse);
      expect(result.languageHint, 'zh');
    });
  });
}
