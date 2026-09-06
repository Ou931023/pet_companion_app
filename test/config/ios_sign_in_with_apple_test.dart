import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('iOS Sign in with Apple readiness', () {
    final entitlements =
        File('ios/Runner/Runner.entitlements').readAsStringSync();
    final project =
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();

    test('Runner declares the Sign in with Apple entitlement', () {
      expect(entitlements, contains('com.apple.developer.applesignin'));
      expect(entitlements, contains('<string>Default</string>'));
    });

    test('Xcode target enables Sign in with Apple capability', () {
      expect(project, contains('com.apple.SignInWithApple'));
      expect(project, contains('enabled = 1'));
    });

    test('Release store build uses the Apple entitlement file', () {
      final matches = RegExp(
        r'CODE_SIGN_ENTITLEMENTS = Runner/Runner\.entitlements;',
      ).allMatches(project);

      expect(matches.length, 1,
          reason: 'Release 必須接上 entitlement；Debug/Profile 要支援 Personal Team');
    });

    test('Debug and Profile do not request Personal Team capabilities', () {
      for (final pattern in <String>[
        r'97C147061CF9000F007C117D /\* Debug \*/ = \{[\s\S]*?name = Debug;\s*\};',
        r'249021D4217E4FDB00AE95B9 /\* Profile \*/ = \{[\s\S]*?name = Profile;\s*\};',
      ]) {
        final localConfig = RegExp(pattern).firstMatch(project)?.group(0);
        expect(localConfig, isNotNull);
        expect(localConfig, isNot(contains('CODE_SIGN_ENTITLEMENTS')));
      }
    });
  });
}
