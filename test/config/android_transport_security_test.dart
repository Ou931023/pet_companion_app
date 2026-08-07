import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Android transport security（CR-0096S Batch 2）', () {
    test('main manifest 不再讓 release 全域允許 cleartext', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

      expect(
          manifest,
          contains(
              'android:networkSecurityConfig="@xml/network_security_config"'));
      expect(manifest, isNot(contains('android:usesCleartextTraffic="true"')));
    });

    test('release network security config 禁止明文 HTTP', () {
      final config = File(
        'android/app/src/main/res/xml/network_security_config.xml',
      ).readAsStringSync();

      expect(config, contains('cleartextTrafficPermitted="false"'));
      expect(config, isNot(contains('cleartextTrafficPermitted="true"')));
    });

    test('debug/profile 保留本機開發 HTTP 能力', () {
      final debugConfig = File(
        'android/app/src/debug/res/xml/network_security_config.xml',
      ).readAsStringSync();
      final profileConfig = File(
        'android/app/src/profile/res/xml/network_security_config.xml',
      ).readAsStringSync();

      expect(debugConfig, contains('cleartextTrafficPermitted="true"'));
      expect(profileConfig, contains('cleartextTrafficPermitted="true"'));
    });
  });
}
