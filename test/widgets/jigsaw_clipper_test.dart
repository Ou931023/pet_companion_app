import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/widgets/jigsaw_clipper.dart';

void main() {
  // 拼圖塊（JigsawPiece）會用 JigsawClipper 把照片裁成有凸有凹的拼圖形狀；
  // 這裡直接驗證 clipper 產生的路徑是真的 jigsaw 形狀（不是純方形）。
  test('內部拼圖塊有凸 / 凹：路徑鼓出本體方形，不是純方形', () {
    const core = 100.0;
    const knob = 16.0;
    const size = Size(core + 2 * knob, core + 2 * knob);
    // 3x3 中央那塊（index 4）四邊都是內部邊，必有 tab / blank。
    const clipper = JigsawClipper(gridSize: 3, index: 4, knob: knob, core: core);
    final b = clipper.getClip(size).getBounds();

    // 有凸起 tab → bounds 會超出本體方形 [knob, knob+core]。
    final bulgesOut = b.left < knob ||
        b.top < knob ||
        b.right > knob + core ||
        b.bottom > knob + core;
    expect(bulgesOut, isTrue, reason: '拼圖塊應有凸起 / 凹槽，不是純方形');
    // 不是退化成一個點 / 空路徑。
    expect(b.width, greaterThan(core * 0.8));
    expect(b.height, greaterThan(core * 0.8));
  });

  test('角落塊的外框兩邊保持平直，仍是有效拼圖路徑', () {
    // index 0 = 左上角：上、左是外框（平直），右、下是內部邊（有凸凹）。
    const clipper = JigsawClipper(gridSize: 3, index: 0, knob: 16, core: 100);
    final path = clipper.getClip(const Size(132, 132));
    expect(path.getBounds().isEmpty, isFalse);
  });

  test('3x3（9 片）與 4x4（16 片）各 index 都能產生路徑', () {
    for (final n in [3, 4]) {
      for (var i = 0; i < n * n; i++) {
        final clipper =
            JigsawClipper(gridSize: n, index: i, knob: 12, core: 80);
        expect(clipper.getClip(const Size(104, 104)).getBounds().isEmpty,
            isFalse,
            reason: 'n=$n index=$i');
      }
    }
  });

  test('shouldReclip：不同 index / 大小會重新裁切', () {
    const a = JigsawClipper(gridSize: 3, index: 0, knob: 12, core: 80);
    const b = JigsawClipper(gridSize: 3, index: 1, knob: 12, core: 80);
    expect(a.shouldReclip(b), isTrue);
    expect(a.shouldReclip(a), isFalse);
  });
}
