import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('iOS transport security（CR-0096S Batch 3）', () {
    test('Info.plist 不再全域允許 arbitrary loads', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();

      expect(plist, contains('<key>NSAppTransportSecurity</key>'));
      expect(plist, contains('<key>NSAllowsArbitraryLoads</key>'));
      expect(plist, contains('<false/>'));
      expect(plist,
          isNot(contains('<key>NSAllowsArbitraryLoads</key>\n\t\t<true/>')));
    });

    test('Info.plist 保留 local networking 供本機與區網開發', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();

      expect(plist, contains('<key>NSAllowsLocalNetworking</key>'));
      expect(
          plist, contains('<key>NSAllowsLocalNetworking</key>\n\t\t<true/>'));
    });

    test('iOS 權限文案不含 demo/debug/test/mock 工程字樣', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      final banned =
          RegExp(r'\b(demo|debug|test|mock)\b', caseSensitive: false);

      for (final key in <String>[
        'NSCameraUsageDescription',
        'NSLocalNetworkUsageDescription',
        'NSMicrophoneUsageDescription',
        'NSPhotoLibraryAddUsageDescription',
        'NSPhotoLibraryUsageDescription',
        'NSSpeechRecognitionUsageDescription',
      ]) {
        final keyIndex = plist.indexOf('<key>$key</key>');
        expect(keyIndex, isNonNegative, reason: '$key must exist');
        final valueStart = plist.indexOf('<string>', keyIndex);
        final valueEnd = plist.indexOf('</string>', valueStart);
        expect(valueStart, isNonNegative,
            reason: '$key must have string value');
        expect(valueEnd, isNonNegative, reason: '$key must close string value');

        final value = plist.substring(valueStart, valueEnd);
        expect(value, isNot(matches(banned)),
            reason: '$key should be store-safe');
      }
    });
  });
}
