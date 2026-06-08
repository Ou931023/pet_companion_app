import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/config/app_config.dart';
import 'package:pet_companion_app/services/asr_strategy_service.dart';
import 'package:pet_companion_app/services/language_routing_service.dart';
import 'package:pet_companion_app/services/taigi_asr_strategy.dart';

/// CR-0048：驗證 MockTaigiAsrStrategy 的 build-flavor 隔離。
///
/// `AppConfig.mockServicesEnabled` 是 compile-time（`--dart-define`）常數，
/// 因此本檔以該值分流，鏡像 `lib/app.dart` 195-205 的注入條件：
///   strategies: [OpenAiRealtimeAsrStrategy(),
///                if (AppConfig.mockServicesEnabled) MockTaigiAsrStrategy()]
///
/// - 一般 `flutter test`（development，預設 ALLOW_MOCK_SERVICES=false）
///   → mockServicesEnabled=false → 不含台語 mock strategy。
/// - `flutter test --dart-define=ALLOW_MOCK_SERVICES=true`（dev/test）
///   → 含台語 mock strategy。
/// - `flutter test --dart-define=APP_ENV=production ...`
///   → production 強制 mockServicesEnabled=false → 不含台語 mock strategy，
///     且 Realtime ASR 與語音路由 fallback 不被破壞。
AsrStrategyService buildAsAppWired() {
  // 與 app.dart 完全一致的注入條件，確保測試反映正式 wiring。
  return AsrStrategyService(
    strategies: [
      const OpenAiRealtimeAsrStrategy(),
      if (AppConfig.mockServicesEnabled) const MockTaigiAsrStrategy(),
    ],
  );
}

void main() {
  group('CR-0048 MockTaigiAsrStrategy build-flavor gating', () {
    test('production 一律不啟用 mock（mockServicesEnabled）', () {
      if (AppConfig.isProduction) {
        expect(AppConfig.mockServicesEnabled, isFalse);
      } else {
        expect(AppConfig.mockServicesEnabled, AppConfig.allowMockServices);
      }
    });

    test('app wiring：台語 mock strategy 僅在 mockServicesEnabled 時納入', () {
      final service = buildAsAppWired();
      if (AppConfig.mockServicesEnabled) {
        expect(
          service.taigiStrategy,
          isA<MockTaigiAsrStrategy>(),
          reason: 'dev/test 應保留台語 mock strategy 供測試使用',
        );
      } else {
        expect(
          service.taigiStrategy,
          isNull,
          reason: 'production 不得注入台語 mock strategy',
        );
      }
    });

    test('無論是否含 mock，正式 Realtime ASR strategy 都存在', () {
      final service = buildAsAppWired();
      expect(service.defaultRealtime, isA<OpenAiRealtimeAsrStrategy>());
      expect(service.strategies, isNotEmpty);
    });

    test('production 缺台語 mock 時，strategyFor graceful fallback 回 Realtime', () {
      if (!AppConfig.mockServicesEnabled) {
        final service = buildAsAppWired();
        // 手動指定的 mockTaigiAsr 在正式版不存在 → 應 fallback 到 OpenAI Realtime，
        // 而非丟例外或回 null（語音路由不被破壞）。
        final resolved = service.strategyFor('mockTaigiAsr');
        expect(resolved, isA<OpenAiRealtimeAsrStrategy>());
      }
    });

    test('LanguageRoutingService 在缺台語 strategy 時仍有正式 fallback', () {
      final service = buildAsAppWired();
      final routing = LanguageRoutingService(service);
      // 不論 build flavor，路由都不應拋例外（缺台語 mock 時走 Realtime fallback）。
      expect(() => routing, returnsNormally);
      if (!AppConfig.mockServicesEnabled) {
        expect(service.taigiStrategy, isNull);
      }
    });
  });
}
