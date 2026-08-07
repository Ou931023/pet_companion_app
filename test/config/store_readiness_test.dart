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

    test('icon readiness includes iOS and Android adaptive assets', () {
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
      expect(
        _pngSize(
          'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
          'Icon-App-1024x1024@1x.png',
        ),
        const _ImageSize(1024, 1024),
      );

      const adaptiveIconPath =
          'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml';
      final adaptiveIcon = File(adaptiveIconPath);
      expect(adaptiveIcon.existsSync(), isTrue);
      expect(
          _read(adaptiveIconPath), contains('@mipmap/ic_launcher_foreground'));
      expect(
          _read(adaptiveIconPath), contains('@color/ic_launcher_background'));
      expect(
        File('android/app/src/main/res/mipmap-xxxhdpi/'
                'ic_launcher_foreground.png')
            .existsSync(),
        isTrue,
      );
      expect(
        File('store_assets/play_store_icon_512.png').existsSync(),
        isTrue,
      );
      expect(
        _pngSize('store_assets/play_store_icon_512.png'),
        const _ImageSize(512, 512),
      );
      expect(assetChecklist, contains('Android adaptive icon：✅'));
    });

    test('store metadata does not advertise production-hidden features', () {
      final metadata = _read('docs/APP_STORE_METADATA.md');

      expect(metadata, contains('本版停用功能'));
      expect(metadata, contains('不得宣稱已可用'));
      expect(metadata, contains('marketplace'));
      expect(metadata, contains('daily-care'));
    });

    test('static legal site is present with official support contact', () {
      final requiredPages = [
        'store_legal_site/index.html',
        'store_legal_site/privacy.html',
        'store_legal_site/terms.html',
        'store_legal_site/support.html',
        'store_legal_site/styles.css',
        'store_legal_site/assets/icon-512.png',
        '.github/workflows/legal-site-pages.yml',
      ];

      for (final path in requiredPages) {
        expect(File(path).existsSync(), isTrue, reason: '$path should exist');
      }

      expect(_pngSize('store_legal_site/assets/icon-512.png'),
          const _ImageSize(512, 512));

      final privacy = _read('store_legal_site/privacy.html');
      final terms = _read('store_legal_site/terms.html');
      final support = _read('store_legal_site/support.html');
      final readme = _read('store_legal_site/README.md');
      final workflow = _read('.github/workflows/legal-site-pages.yml');

      expect(privacy, contains('使用紀錄'));
      expect(privacy, contains('OpenAI'));
      expect(privacy, contains('不是醫療診斷'));
      expect(terms, contains('不能取代醫師'));
      expect(support, contains('刪除帳號與資料'));
      expect(
        privacy,
        contains('mailto:aicompanion.support@gmail.com'),
      );
      expect(
        terms,
        contains('mailto:aicompanion.support@gmail.com'),
      );
      expect(
        support,
        contains('mailto:aicompanion.support@gmail.com'),
      );
      expect(readme, contains('PRIVACY_POLICY_URL'));
      expect(readme, contains('TERMS_OF_SERVICE_URL'));
      expect(readme, contains('SUPPORT_URL'));
      expect(
        readme,
        contains('--dart-define=CONTACT_EMAIL=aicompanion.support@gmail.com'),
      );
      expect(readme, contains('https://ou931023.github.io/pet_companion_app'));
      expect(workflow, contains('Deploy legal site to GitHub Pages'));
      expect(workflow, contains('pages: write'));
      expect(workflow, contains('id-token: write'));
      expect(workflow, contains('workflow_dispatch'));
      expect(workflow, contains('path: store_legal_site'));
      expect(workflow, contains('actions/deploy-pages@v4'));

      expect(privacy, isNot(contains('上架前必填')));
      expect(terms, isNot(contains('上架前必填')));
      expect(support, isNot(contains('上架前必填')));
    });
  });
}

String _read(String path) => File(path).readAsStringSync();

_ImageSize _pngSize(String path) {
  final bytes = File(path).readAsBytesSync();
  expect(bytes.take(8).toList(), [137, 80, 78, 71, 13, 10, 26, 10]);
  return _ImageSize(_readUint32(bytes, 16), _readUint32(bytes, 20));
}

int _readUint32(List<int> bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

class _ImageSize {
  const _ImageSize(this.width, this.height);

  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is _ImageSize && width == other.width && height == other.height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => '${width}x$height';
}
