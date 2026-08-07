import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/config/app_config.dart';
import 'package:pet_companion_app/config/legal_config.dart';

void main() {
  group('Store submission readiness', () {
    test('single smoke runbook exists and names the required blockers', () {
      final runbook = _read('docs/STORE_SUBMISSION_RUNBOOK.md');

      expect(runbook, contains('Store Submission Smoke Runbook'));
      expect(runbook, contains('flutter analyze'));
      expect(runbook, contains('flutter test'));
      expect(runbook, contains('flutter build ipa --release'));
      expect(runbook, contains('flutter build appbundle --release'));
      expect(runbook, contains('API_BASE_URL=https://'));
      expect(runbook, contains('PRIVACY_POLICY_URL=https://'));
      expect(runbook, contains('TERMS_OF_SERVICE_URL=https://'));
      expect(runbook, contains('SUPPORT_URL=https://'));
      expect(runbook, contains('CONTACT_EMAIL='));
      expect(runbook, contains('app_usage_events'));
      expect(runbook, contains('管理者 / 照護者後台 analytics'));
      expect(runbook, contains('Android adaptive icon'));
      expect(runbook, contains('screenshots'));
      expect(runbook, contains('No-Go'));
    });

    test('store documents point to the executable runbook', () {
      expect(
        _read('docs/STORE_RELEASE_CHECKLIST.md'),
        contains('docs/STORE_SUBMISSION_RUNBOOK.md'),
      );
      expect(
        _read('docs/PRODUCTION_CONFIG_CHECKLIST.md'),
        contains('docs/STORE_SUBMISSION_RUNBOOK.md'),
      );
      expect(
        _read('docs/STORE_ASSET_CHECKLIST.md'),
        contains('docs/STORE_SUBMISSION_RUNBOOK.md'),
      );
    });

    test('production gates ignore accidental store-facing debug flags', () {
      if (!AppConfig.isProduction) return;

      expect(AppConfig.demoLoginVisible, isFalse);
      expect(AppConfig.socialSignInVisible, isFalse);
      expect(AppConfig.marketplaceVisible, isFalse);
      expect(AppConfig.dailyCareTasksVisible, isFalse);
      expect(AppConfig.devPanelsVisible, isFalse);
      expect(AppConfig.mockServicesEnabled, isFalse);
      expect(AppConfig.freeAllPetSkinsEnabled, isFalse);
    });

    test('production API base URL must be hosted HTTPS', () {
      if (!AppConfig.isProduction) return;

      final uri = Uri.tryParse(AppConfig.apiBaseUrl.trim());
      expect(uri, isNotNull);
      expect(uri!.scheme, 'https');
      expect(AppConfig.legacyBackendHosts, isNot(contains(uri.host)));
      expect(AppConfig.isApiBaseUrlProductionSafe, isTrue);
    });

    test('legal config stays blocked until all hosted values are injected', () {
      final values = [
        LegalConfig.privacyPolicyUrl,
        LegalConfig.termsOfServiceUrl,
        LegalConfig.supportUrl,
        LegalConfig.contactEmail,
      ];

      final placeholders = values.map(LegalConfig.isPlaceholder);
      if (placeholders.any((value) => value)) {
        expect(LegalConfig.areStoreLegalLinksConfigured, isFalse);
      } else {
        expect(LegalConfig.areStoreLegalLinksConfigured, isTrue);
        expect(LegalConfig.privacyPolicyUrl, startsWith('https://'));
        expect(LegalConfig.termsOfServiceUrl, startsWith('https://'));
        expect(LegalConfig.supportUrl, startsWith('https://'));
        expect(LegalConfig.contactEmail, contains('@'));
      }
    });

    test('transport security release defaults block cleartext traffic', () {
      final networkSecurity =
          _read('android/app/src/main/res/xml/network_security_config.xml');
      final infoPlist = _read('ios/Runner/Info.plist');

      expect(networkSecurity, contains('cleartextTrafficPermitted="false"'));
      expect(infoPlist, contains('<key>NSAllowsArbitraryLoads</key>'));
      expect(infoPlist, contains('<false/>'));
    });

    test('icon readiness distinguishes present assets from owner blockers', () {
      final iosIconContents =
          _read('ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json');
      final assetChecklist = _read('docs/STORE_ASSET_CHECKLIST.md');

      expect(iosIconContents, contains('Icon-App-1024x1024@1x.png'));
      expect(
        File('ios/Runner/Assets.xcassets/AppIcon.appiconset/'
                'Icon-App-1024x1024@1x.png')
            .existsSync(),
        isTrue,
      );

      final adaptiveIcon =
          File('android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml');
      if (!adaptiveIcon.existsSync()) {
        expect(assetChecklist, contains('無 adaptive icon'));
        expect(assetChecklist, contains('mipmap-anydpi-v26/ic_launcher.xml'));
        expect(assetChecklist, contains('BLOCKER'));
      }
    });

    test('store metadata does not advertise production-hidden features', () {
      final metadata = _read('docs/APP_STORE_METADATA.md');

      expect(metadata, contains('本版停用功能'));
      expect(metadata, contains('不得宣稱已可用'));
      expect(metadata, contains('marketplace'));
      expect(metadata, contains('daily-care'));
    });
  });
}

String _read(String path) => File(path).readAsStringSync();
