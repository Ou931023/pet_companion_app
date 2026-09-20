import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> alphaOf(String path) async {
  final codec = await ui.instantiateImageCodec(await File(path).readAsBytes());
  final frame = await codec.getNextFrame();
  try {
    expect(frame.image.width, 1024, reason: path);
    expect(frame.image.height, 1024, reason: path);
    final data =
        (await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final rgba =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final alpha = Uint8List(1024 * 1024);
    for (var i = 0; i < alpha.length; i++) {
      alpha[i] = rgba[i * 4 + 3];
    }
    expect([
      alpha.first,
      alpha[1023],
      alpha[1024 * 1023],
      alpha.last
    ], everyElement(0), reason: '$path must not contain a baked background');
    expect(alpha.where((value) => value == 255).length,
        greaterThan(alpha.length ~/ 5),
        reason: '$path must have an opaque body');
    return alpha;
  } finally {
    frame.image.dispose();
    codec.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final skin in ['fox', 'guinea_pig']) {
    test(
        '$skin expressions and animation frames preserve the master silhouette',
        () async {
      final master = await alphaOf('assets/pets/states/${skin}_normal.png');
      final paths = [
        for (final state in [
          'happy',
          'caring',
          'sad',
          'sleepy',
          'excited',
          'hungry',
          'thirsty'
        ])
          'assets/pets/states/${skin}_$state.png',
        'assets/pets/listening/${skin}_listening.png',
        for (var i = 1; i <= 3; i++) 'assets/pets/rest/${skin}_rest_0$i.png',
        for (var i = 1; i <= (skin == 'fox' ? 6 : 3); i++)
          'assets/pets/talk/${skin}_talk_0$i.png',
      ];
      for (final path in paths) {
        final alpha = await alphaOf(path);
        var differences = 0;
        for (var i = 0; i < master.length; i++) {
          if (alpha[i] != master[i]) differences++;
        }
        expect(differences, 0,
            reason: '$path changes the body outline or baseline');
      }
    });
  }
}
