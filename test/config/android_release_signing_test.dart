import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Android release signing readiness', () {
    test('release build does not use debug signing config', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();

      expect(gradle, contains('signingConfigs.getByName("release")'));
      expect(gradle, isNot(contains('signingConfigs.getByName("debug")')));
      expect(
        gradle,
        isNot(contains('signingConfig = signingConfigs.getByName("debug")')),
      );
    });

    test(
      'release signing reads local key.properties without committing secrets',
      () {
        final gradle = File('android/app/build.gradle.kts').readAsStringSync();
        final gitignore = File('.gitignore').readAsStringSync();

        expect(gradle, contains('rootProject.file("key.properties")'));
        expect(gradle, contains('storePassword'));
        expect(gradle, contains('keyPassword'));
        expect(gradle, contains('keyAlias'));
        expect(gradle, contains('storeFile'));
        expect(gradle, contains('Missing Android release signing config'));

        expect(gitignore, contains('android/key.properties'));
        expect(gitignore, contains('**/*.jks'));
        expect(gitignore, contains('**/*.keystore'));
      },
    );

    test('release signing runbook and script are executable without secrets',
        () {
      final runbook = File('docs/RELEASE_SIGNING.md').readAsStringSync();
      final storeRunbook =
          File('docs/STORE_SUBMISSION_RUNBOOK.md').readAsStringSync();
      final script =
          File('scripts/check_release_signing_readiness.sh').readAsStringSync();

      expect(
          runbook, contains('bash scripts/check_release_signing_readiness.sh'));
      expect(runbook, contains('flutter build appbundle --release'));
      expect(runbook, contains('flutter build ipa --release'));
      expect(runbook, contains('ANDROID_KEYSTORE_BASE64'));
      expect(runbook, contains('APP_STORE_CONNECT_API_KEY_P8'));
      expect(runbook, contains('No-Go'));
      expect(runbook, contains('tw.edu.ncyu.im.aicompanion'));
      expect(runbook, contains('aicompanion.support@gmail.com'));

      expect(storeRunbook,
          contains('bash scripts/check_release_signing_readiness.sh'));
      expect(
          storeRunbook,
          contains(
              'https://ou931023.github.io/pet_companion_app/privacy.html'));
      expect(storeRunbook,
          contains('https://ou931023.github.io/pet_companion_app/terms.html'));
      expect(
          storeRunbook,
          contains(
              'https://ou931023.github.io/pet_companion_app/support.html'));

      expect(script, contains('git check-ignore -q android/key.properties'));
      expect(script, contains('Release signing readiness checks completed'));
      expect(script, contains('contents were not read'));
      expect(script, contains('No tracked signing key or certificate files'));
      expect(script, isNot(contains('cat android/key.properties')));
      expect(script, isNot(contains('source android/key.properties')));
      expect(script, isNot(contains('storePassword=')));
      expect(script, isNot(contains('keyPassword=')));
    });
  });
}
