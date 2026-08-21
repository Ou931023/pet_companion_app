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
      expect(
        runbook,
        contains('node scripts/check_caregiver_web_config.js caregiver_web/config.js'),
      );
      expect(runbook, contains('app.js?v=20260821-cr0103'));
      expect(runbook, contains('https://ai-companion-api-rdjv.onrender.com/api'));
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
      expect(
        _read('docs/STORE_SUBMISSION_RUNBOOK.md'),
        contains('docs/INTERNAL_TESTING_SMOKE_RUNBOOK.md'),
      );
      expect(
        _read('docs/STORE_SUBMISSION_RUNBOOK.md'),
        contains('docs/FINAL_STORE_BLOCKER_BOARD.md'),
      );
      expect(
        _read('docs/STORE_SUBMISSION_RUNBOOK.md'),
        contains('docs/STORE_REVIEW_NOTES_TEMPLATE.md'),
      );
      expect(
        _read('docs/STORE_SUBMISSION_RUNBOOK.md'),
        contains('docs/BACKEND_DEPLOYMENT_GUIDE.md'),
      );
      expect(
        _read('docs/BACKEND_DEPLOYMENT_GUIDE.md'),
        contains('docs/CAREGIVER_OPERATIONS_RUNBOOK.md'),
      );
      expect(
        _read('docs/STORE_RELEASE_CHECKLIST.md'),
        contains('docs/FINAL_STORE_BLOCKER_BOARD.md'),
      );
      expect(
        _read('docs/PRODUCTION_CONFIG_CHECKLIST.md'),
        contains('docs/FINAL_STORE_BLOCKER_BOARD.md'),
      );
    });

    test('caregiver operations runbook covers analytics handoff and Telegram', () {
      final runbook = _read('docs/CAREGIVER_OPERATIONS_RUNBOOK.md');

      expect(runbook, contains('Caregiver Operations Runbook'));
      expect(runbook, contains('POST /api/app-usage/events'));
      expect(runbook, contains('GET /api/caregiver/analytics'));
      expect(runbook, contains('app_usage_events'));
      expect(runbook, contains('resident_caregiver_links'));
      expect(runbook, contains('照護人員只能以自己的 Firebase 帳號 / ID Token'));
      expect(runbook, contains('不可以把 `ADMIN_API_TOKEN` 給一般照護人員'));
      expect(runbook, contains('TELEGRAM_CARE_CHAT_ID'));
      expect(runbook, contains('TELEGRAM_BOT_TOKEN'));
      expect(runbook, contains('low` / `medium`'));
      expect(runbook, contains('high` / `urgent`'));
      expect(runbook, contains('window.APP_CONFIG'));
      expect(runbook, contains('Firebase Console'));
      expect(runbook, contains('Authorized domains'));
      expect(runbook, contains('check_caregiver_web_config.js'));
      expect(runbook, contains('CAREGIVER_WEB_API_BASE_URL'));
      expect(runbook, contains('CR-0104 Per-Caregiver Telegram Routing'));
      expect(runbook, contains('No-Go'));
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
      expect(
        File('store_assets/play_feature_graphic_1024x500.png').existsSync(),
        isTrue,
      );
      expect(
        _pngSize('store_assets/play_feature_graphic_1024x500.png'),
        const _ImageSize(1024, 500),
      );
      final androidScreenshots = [
        'store_assets/screenshots/android_phone/01_home_voice.png',
        'store_assets/screenshots/android_phone/02_voice_conversation.png',
        'store_assets/screenshots/android_phone/03_memory.png',
        'store_assets/screenshots/android_phone/04_care_alert.png',
        'store_assets/screenshots/android_phone/05_privacy_support.png',
      ];
      final iosScreenshots = [
        'store_assets/screenshots/ios_6_7/01_home_voice.png',
        'store_assets/screenshots/ios_6_7/02_voice_conversation.png',
        'store_assets/screenshots/ios_6_7/03_memory.png',
        'store_assets/screenshots/ios_6_7/04_care_alert.png',
        'store_assets/screenshots/ios_6_7/05_privacy_support.png',
      ];

      for (final path in androidScreenshots) {
        expect(File(path).existsSync(), isTrue, reason: '$path should exist');
        expect(_pngSize(path), const _ImageSize(1080, 1920));
      }

      for (final path in iosScreenshots) {
        expect(File(path).existsSync(), isTrue, reason: '$path should exist');
        expect(_pngSize(path), const _ImageSize(1290, 2796));
      }

      final screenshotScript = _read('scripts/generate_store_screenshots.sh');
      expect(screenshotScript, contains('非醫療診斷'));
      expect(screenshotScript, isNot(contains('debug')));
      expect(screenshotScript, isNot(contains('demo')));
      expect(screenshotScript, isNot(contains('mock')));
      expect(assetChecklist, contains('Android adaptive icon：✅'));
      expect(assetChecklist, contains('screenshots：✅'));
    });

    test('launch screen and display names use production branding', () {
      final infoPlist = _read('ios/Runner/Info.plist');
      final androidManifest = _read('android/app/src/main/AndroidManifest.xml');
      final iosLaunchStoryboard =
          _read('ios/Runner/Base.lproj/LaunchScreen.storyboard');
      final androidLaunch =
          _read('android/app/src/main/res/drawable/launch_background.xml');
      final androidLaunchV21 =
          _read('android/app/src/main/res/drawable-v21/launch_background.xml');
      final colors = _read('android/app/src/main/res/values/colors.xml');
      final assetChecklist = _read('docs/STORE_ASSET_CHECKLIST.md');

      expect(infoPlist, contains('<string>AI陪伴</string>'));
      expect(androidManifest, contains('android:label="AI陪伴"'));
      expect(iosLaunchStoryboard, contains('LaunchImage'));

      for (final path in [
        'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage.png',
        'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@2x.png',
        'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png',
      ]) {
        final size = _pngSize(path);
        expect(size.width, greaterThanOrEqualTo(168));
        expect(size.height, greaterThanOrEqualTo(168));
      }

      expect(androidLaunch, contains('@color/launch_background'));
      expect(androidLaunch, contains('@drawable/launch_brand'));
      expect(androidLaunch, isNot(contains('@android:color/white')));
      expect(androidLaunch, isNot(contains('launch_image')));
      expect(androidLaunchV21, contains('@color/launch_background'));
      expect(androidLaunchV21, contains('@drawable/launch_brand'));
      expect(androidLaunchV21, isNot(contains('?android:colorBackground')));
      expect(androidLaunchV21, isNot(contains('launch_image')));
      expect(
          colors, contains('<color name="launch_background">#FFF8EA</color>'));
      expect(
        _pngSize('android/app/src/main/res/drawable-nodpi/launch_brand.png'),
        const _ImageSize(240, 240),
      );
      expect(assetChecklist, contains('launch screen：✅'));
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
      expect(support, contains('帳號與資料刪除申請'));
      expect(support, contains('AI陪伴帳號刪除申請'));
      expect(support, contains('使用分析紀錄'));
      expect(support, contains('不要在信件中提供密碼'));
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

    test('internal testing smoke runbook covers app, data, and store gates',
        () {
      final runbook = _read('docs/INTERNAL_TESTING_SMOKE_RUNBOOK.md');

      expect(runbook,
          contains('TestFlight / Play Internal Testing Smoke Runbook'));
      expect(runbook, contains('API_BASE_URL=https://'));
      expect(
          runbook,
          contains(
              'https://ou931023.github.io/pet_companion_app/privacy.html'));
      expect(runbook,
          contains('https://ou931023.github.io/pet_companion_app/terms.html'));
      expect(
          runbook,
          contains(
              'https://ou931023.github.io/pet_companion_app/support.html'));
      expect(runbook, contains('aicompanion.support@gmail.com'));
      expect(runbook, contains('flutter analyze'));
      expect(runbook, contains('flutter test'));
      expect(
          runbook, contains('bash scripts/check_release_signing_readiness.sh'));
      expect(runbook, contains('flutter build ipa --release'));
      expect(runbook, contains('flutter build appbundle --release'));
      expect(runbook, contains('Realtime 語音'));
      expect(runbook, contains('Care Alert Smoke'));
      expect(runbook, contains('app_usage_events'));
      expect(runbook, contains('voice_interaction_start'));
      expect(runbook, contains('voice_interaction_end'));
      expect(runbook, contains('typed_chat_sent'));
      expect(runbook, contains('pet_interaction'));
      expect(runbook, contains('reminder_created'));
      expect(runbook, contains('puzzle_started'));
      expect(runbook, contains('puzzle_completed'));
      expect(runbook, contains('管理者 analytics'));
      expect(runbook, contains('caregiver_web 顯示真實彙整'));
      expect(runbook, contains('帳號刪除'));
      expect(runbook, contains('Data Safety'));
      expect(runbook, contains('非醫療診斷'));
      expect(runbook, contains('No-Go'));

      for (final forbidden in [
        'localhost',
        '127.0.0.1',
        '10.0.2.2',
        'ngrok',
      ]) {
        expect(runbook, isNot(contains(forbidden)));
      }
    });

    test('final store blocker board separates completed and owner-gated work',
        () {
      final board = _read('docs/FINAL_STORE_BLOCKER_BOARD.md');

      expect(board, contains('Final Store Blocker Board'));
      expect(board, contains('已由 repo 端完成'));
      expect(board, contains('Owner 必須提供'));
      expect(board, contains('必須真機驗證'));
      expect(board, contains('商店後台必填'));
      expect(board, contains('最後執行順序'));
      expect(board, contains('No-Go'));
      expect(board, contains('AI陪伴'));
      expect(board, contains('tw.edu.ncyu.im.aicompanion'));
      expect(
          board,
          contains(
              'https://ou931023.github.io/pet_companion_app/privacy.html'));
      expect(board,
          contains('https://ou931023.github.io/pet_companion_app/terms.html'));
      expect(
          board,
          contains(
              'https://ou931023.github.io/pet_companion_app/support.html'));
      expect(board, contains('aicompanion.support@gmail.com'));
      expect(board, contains('Production API'));
      expect(board, contains('Android signing'));
      expect(board, contains('iOS signing'));
      expect(board, contains('iPhone pairing'));
      expect(board, contains('Realtime 語音'));
      expect(board, contains('Care Alert'));
      expect(board, contains('app_usage_events'));
      expect(board, contains('caregiver_web analytics'));
      expect(board, contains('Data Safety'));
      expect(board, contains('非醫療診斷'));
      expect(
          board, contains('bash scripts/check_release_signing_readiness.sh'));
      expect(board, contains('docs/STORE_REVIEW_NOTES_TEMPLATE.md'));

      for (final forbidden in [
        'API_BASE_URL=http://',
        'debug key 送審',
      ]) {
        expect(board, isNot(contains(forbidden)));
      }
    });

    test('backend deployment guide covers Render and Neon production setup',
        () {
      final guide = _read('docs/BACKEND_DEPLOYMENT_GUIDE.md');
      final runbook = _read('docs/STORE_SUBMISSION_RUNBOOK.md');

      expect(guide, contains('Render + Neon'));
      expect(guide, contains('Render Web Service'));
      expect(guide, contains('Neon Postgres'));
      expect(guide, contains('GitHub Pages legal/support site'));
      expect(guide, contains('Root Directory'));
      expect(guide, contains('backend/stt_proxy'));
      expect(guide, contains('Build Command'));
      expect(guide, contains('npm ci'));
      expect(guide, contains('Start Command'));
      expect(guide, contains('node server.js'));
      expect(guide, contains('Health Check Path'));
      expect(guide, contains('/health'));
      expect(guide, contains('DATABASE_URL'));
      expect(guide, contains('OPENAI_API_KEY'));
      expect(guide, contains('CORS_ALLOWED_ORIGINS'));
      expect(guide, contains('FIREBASE_PROJECT_ID'));
      expect(guide, contains('FIREBASE_CLIENT_EMAIL'));
      expect(guide, contains('FIREBASE_PRIVATE_KEY'));
      expect(guide, contains('ADMIN_API_TOKEN'));
      expect(guide, contains('HOST=0.0.0.0'));
      expect(guide, contains('PGVECTOR_ENABLED=true'));
      expect(guide, contains('npm run db:migrate'));
      expect(guide, contains('CREATE EXTENSION IF NOT EXISTS vector'));
      expect(guide, contains('app_usage_events'));
      expect(guide, contains('API_BASE_URL=https://<Render HTTPS URL>'));
      expect(guide, contains('voice_interaction_start'));
      expect(guide, contains('voice_interaction_end'));
      expect(guide, contains('typed_chat_sent'));
      expect(guide, contains('caregiver_web / admin analytics'));
      expect(guide, contains('不進 git'));

      expect(runbook, contains('docs/BACKEND_DEPLOYMENT_GUIDE.md'));
      expect(runbook, contains('Render + Neon'));
      expect(runbook, contains('Neon / production PostgreSQL migrations'));

      for (final forbidden in [
        'OPENAI_API_KEY=sk-',
        'ADMIN_API_TOKEN=',
        'FIREBASE_PRIVATE_KEY=-----BEGIN',
        'DATABASE_URL=postgres://',
      ]) {
        expect(guide, isNot(contains(forbidden)));
      }
    });

    test('store review notes template keeps reviewer access safe', () {
      final template = _read('docs/STORE_REVIEW_NOTES_TEMPLATE.md');
      final metadata = _read('docs/APP_STORE_METADATA.md');
      final internalRunbook = _read('docs/INTERNAL_TESTING_SMOKE_RUNBOOK.md');

      expect(template, contains('Store Review Notes'));
      expect(template, contains('App Store Connect Review Notes'));
      expect(template, contains('Google Play Review'));
      expect(template, contains('Resident account'));
      expect(template, contains('Password'));
      expect(template, contains('麥克風用途'));
      expect(template, contains('OpenAI Realtime'));
      expect(template, contains('Care Alert'));
      expect(template, contains('不是醫療診斷'));
      expect(template, contains('Email login / Email register'));
      expect(template, contains('帳號刪除'));
      expect(template, contains('Data Safety'));
      expect(template, contains('App Store Privacy'));
      expect(template, contains('aicompanion.support@gmail.com'));
      expect(
          template,
          contains(
              'https://ou931023.github.io/pet_companion_app/privacy.html'));
      expect(template,
          contains('https://ou931023.github.io/pet_companion_app/terms.html'));
      expect(
          template,
          contains(
              'https://ou931023.github.io/pet_companion_app/support.html'));
      expect(template, contains('不寫入 repo'));
      expect(template, contains('No-Go'));

      for (final forbidden in [
        'sk-',
        'DATABASE_URL=',
        'storePassword=',
        'keyPassword=',
        'BEGIN PRIVATE KEY',
      ]) {
        expect(template, isNot(contains(forbidden)));
      }

      expect(metadata, contains('docs/STORE_REVIEW_NOTES_TEMPLATE.md'));
      expect(internalRunbook, contains('docs/STORE_REVIEW_NOTES_TEMPLATE.md'));
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
