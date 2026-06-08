// AppLog helper 單元測試（CR-0047 Batch 3）。
//
// 守護「遮蔽 / 截斷」邏輯：token、逐字稿、Care Alert 摘要永遠不會被完整輸出。
// 注意：release 抑制（kReleaseMode no-op）無法在一般 test build 驗證，
// 此處只測純函式的遮蔽結果。

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/utils/app_log.dart';

void main() {
  group('AppLog.previewTranscript', () {
    test('null / 空字串給安全標記，不丟例外', () {
      expect(AppLog.previewTranscript(null), '(null)');
      expect(AppLog.previewTranscript('   '), '(empty)');
    });

    test('長逐字稿只保留前幾字 + 長度，不外洩完整內容', () {
      const transcript = '我今天覺得有點孤單，晚上也睡不太好，想找人說說話';
      final preview = AppLog.previewTranscript(transcript);
      expect(preview, isNot(contains('睡不太好')));
      expect(preview, contains('字'));
      // 不應包含整段內容。
      expect(preview.length, lessThan(transcript.length));
    });
  });

  group('AppLog.redactToken', () {
    test('完整 token 不會原樣出現，只留頭尾', () {
      const token = 'eyJhbGciOiJ-SECRET-TAIL';
      final redacted = AppLog.redactToken(token);
      expect(redacted, isNot(contains('SECRET')));
      expect(redacted, contains('…'));
    });

    test('短 token 全遮蔽；null 給 (none)', () {
      expect(AppLog.redactToken('abc'), '***');
      expect(AppLog.redactToken(null), '(none)');
    });
  });

  group('AppLog.redactSummary', () {
    test('只回傳長度資訊，不含原文', () {
      const summary = '住民提到胸口悶、喘不過氣';
      final redacted = AppLog.redactSummary(summary);
      expect(redacted, isNot(contains('胸口')));
      expect(redacted, contains('摘要'));
    });
  });
}
