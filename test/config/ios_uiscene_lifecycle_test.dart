import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS UIScene registers plugins after the implicit engine exists', () {
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(appDelegate, contains('FlutterImplicitEngineDelegate'));
    expect(appDelegate, contains('didInitializeImplicitFlutterEngine'));
    expect(
      appDelegate,
      contains(
        'GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)',
      ),
    );
    expect(
      appDelegate,
      isNot(contains('GeneratedPluginRegistrant.register(with: self)')),
    );
    expect(
      appDelegate,
      contains('engineBridge.pluginRegistry.registrar'),
    );
  });
}
