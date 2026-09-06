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

    test('all Runner build configurations use the entitlement file', () {
      final matches = RegExp(
        r'CODE_SIGN_ENTITLEMENTS = Runner/Runner\.entitlements;',
      ).allMatches(project);

      expect(matches.length, 3,
          reason: 'Debug/Profile/Release 都必須接上 entitlement');
    });
  });
}
