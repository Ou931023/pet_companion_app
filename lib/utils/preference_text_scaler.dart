import 'package:flutter/material.dart';

/// Keeps the operating system's nonlinear accessibility scaling intact.
class PreferenceTextScaler extends TextScaler {
  const PreferenceTextScaler(this.system, this.preference);

  final TextScaler system;
  final double preference;

  @override
  double scale(double fontSize) => system.scale(fontSize) * preference;

  @override
  double get textScaleFactor => scale(14) / 14;
}
