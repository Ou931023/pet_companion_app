import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/config/app_config.dart';

/// CR-0034：集中環境設定 / production 守門邏輯。
///
/// 旗標是 compile-time（`--dart-define`）常數，因此本檔的斷言依
/// [AppConfig.isProduction] 分流：
/// - 一般 `flutter test`（development）→ 驗證安全預設與別名邏輯。
/// - `flutter test --dart-define=APP_ENV=production ...`（production）→ 驗證
///   開發面板 / Demo 登入 / mock 注入一律關閉，以及 API base URL 守門。
void main() {
  group('AppConfig 環境治理', () {
    test('apiBaseUrl 與 backendBaseUrl 同源（命名別名）', () {
      expect(AppConfig.apiBaseUrl, AppConfig.backendBaseUrl);
    });

    test('mockServicesEnabled 在 production 一律 false', () {
      if (AppConfig.isProduction) {
        expect(AppConfig.mockServicesEnabled, isFalse);
      } else {
        expect(AppConfig.mockServicesEnabled, AppConfig.allowMockServices);
      }
    });

    test('freeAllPetSkinsEnabled 在 production 一律 false（CR-0096S）', () {
      if (AppConfig.isProduction) {
        expect(AppConfig.freeAllPetSkinsEnabled, isFalse);
      } else {
        expect(
          AppConfig.freeAllPetSkinsEnabled,
          AppConfig.freeAllPetSkins,
        );
      }
    });

    test('devPanelsVisible 在 production 一律 false', () {
      if (AppConfig.isProduction) {
        expect(AppConfig.devPanelsVisible, isFalse);
      } else {
        expect(AppConfig.devPanelsVisible, AppConfig.showDevPanels);
      }
    });

    test('demoLoginVisible 在 production 一律 false', () {
      if (AppConfig.isProduction) {
        expect(AppConfig.demoLoginVisible, isFalse);
      } else {
        expect(AppConfig.demoLoginVisible, AppConfig.showDemoLoginButton);
      }
    });

    test('socialSignInVisible 在 production 一律 false（Apple 完成前）', () {
      if (AppConfig.isProduction) {
        expect(AppConfig.socialSignInVisible, isFalse);
      } else {
        expect(AppConfig.socialSignInVisible, AppConfig.showSocialSignIn);
      }
    });

    test('marketplaceVisible 在 production 一律 false（CR-0056 A2）', () {
      if (AppConfig.isProduction) {
        expect(AppConfig.marketplaceVisible, isFalse);
      } else {
        expect(AppConfig.marketplaceVisible, AppConfig.showMarketplace);
      }
    });

    test('dailyCareTasksVisible 依正式功能旗標決定', () {
      expect(AppConfig.dailyCareTasksVisible, AppConfig.showDailyCareTasks);
    });

    test('非 production 時不阻擋（API base URL 守門）', () {
      if (!AppConfig.isProduction) {
        expect(AppConfig.isApiBaseUrlProductionSafe, isTrue);
      }
    });

    test('production + localhost base URL 視為設定不完整', () {
      if (AppConfig.isProduction) {
        final uri = Uri.tryParse(AppConfig.backendBaseUrl.trim());
        final isLocalish = uri == null ||
            !uri.hasScheme ||
            uri.host.isEmpty ||
            AppConfig.legacyBackendHosts.contains(uri.host);
        // localhost / 空 → 不安全；正式網域 → 安全。
        expect(AppConfig.isApiBaseUrlProductionSafe,
            isLocalish ? isFalse : isTrue);
      }
    });

    test('development 預設為安全保守值（不外洩開發工具）', () {
      if (!AppConfig.isProduction) {
        expect(AppConfig.appEnv, 'development');
        expect(AppConfig.showDevPanels, isFalse);
        expect(AppConfig.showDemoLoginButton, isFalse);
        expect(AppConfig.allowMockServices, isFalse);
        expect(AppConfig.freeAllPetSkins, isFalse);
      }
    });
  });
}
