import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/utils/preference_text_scaler.dart';

class _NonlinearScaler extends TextScaler {
  @override
  double scale(double fontSize) =>
      fontSize < 20 ? fontSize * 2 : fontSize * 1.5;
  @override
  double get textScaleFactor => 2;
}

void main() {
  test('font preference preserves nonlinear system scaling at each size', () {
    final scaler = PreferenceTextScaler(_NonlinearScaler(), 1.2);
    expect(scaler.scale(14), closeTo(33.6, .001));
    expect(scaler.scale(28), closeTo(50.4, .001));
  });
}
