import 'dart:io';

bool isIos26OrNewer() {
  if (!Platform.isIOS) return false;

  final match = RegExp(r'(?:Version\s+)?(\d+)(?:[._]\d+)?')
      .firstMatch(Platform.operatingSystemVersion);
  final majorVersion = int.tryParse(match?.group(1) ?? '');
  return majorVersion != null && majorVersion >= 26;
}
