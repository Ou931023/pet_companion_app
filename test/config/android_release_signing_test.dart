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
  });
}
