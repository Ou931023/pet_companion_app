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

    test('正式版不宣告 local networking 例外或權限', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();

      expect(plist, isNot(contains('<key>NSAllowsLocalNetworking</key>')));
      expect(
          plist, isNot(contains('<key>NSLocalNetworkUsageDescription</key>')));
    });

    test('iOS 權限文案不含 demo/debug/test/mock 工程字樣', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      final banned =
          RegExp(r'\b(demo|debug|test|mock)\b', caseSensitive: false);

      for (final key in <String>[
        'NSCameraUsageDescription',
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

    test('iPhone 鎖定直向，避免長者操作時版面意外旋轉', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      final phoneStart =
          plist.indexOf('<key>UISupportedInterfaceOrientations</key>');
      final phoneEnd = plist.indexOf('</array>', phoneStart);
      final phoneOrientations = plist.substring(phoneStart, phoneEnd);

      expect(phoneOrientations, contains('UIInterfaceOrientationPortrait'));
      expect(phoneOrientations,
          isNot(contains('UIInterfaceOrientationLandscape')));
    });
  });
}
