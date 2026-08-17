import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/models/pet_skin.dart';
import 'package:pet_companion_app/models/pet_status.dart';
import 'package:pet_companion_app/models/pet_visual_profile.dart';
import 'package:pet_companion_app/widgets/pet_avatar.dart';

String _firstAssetName(WidgetTester tester) {
  final image = tester.widget<Image>(find.byType(Image).first);
  final provider = image.image as AssetImage;
  return provider.assetName;
}

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('預設外觀為狗狗（talking）', (tester) async {
    await tester.pumpWidget(wrap(const PetAvatar(mode: PetMode.talking)));
    expect(_firstAssetName(tester), startsWith('assets/pets/talk/dog_talk_'));
  });

  testWidgets('依 skin 顯示對應狀態圖（normal）', (tester) async {
    await tester.pumpWidget(
      wrap(const PetAvatar(mode: PetMode.normal, skin: PetSkin.guineaPig)),
    );
    expect(_firstAssetName(tester), 'assets/pets/states/guinea_pig_normal.png');

    await tester.pumpWidget(
      wrap(const PetAvatar(mode: PetMode.normal, skin: PetSkin.fox)),
    );
    expect(_firstAssetName(tester), 'assets/pets/states/fox_normal.png');
  });

  testWidgets('dog realistic 狀態圖與 listening 使用 v2 asset', (tester) async {
    await tester.pumpWidget(
      wrap(const PetAvatar(
        mode: PetMode.talking,
        skin: PetSkin.dog,
        visualStyle: PetVisualStyle.realistic,
      )),
    );
    expect(
      _firstAssetName(tester),
      startsWith('assets/pets/v2/realistic/adult/dog/talk/talk_'),
    );

    await tester.pumpWidget(
      wrap(const PetAvatar(
        mode: PetMode.rest,
        skin: PetSkin.dog,
        visualStyle: PetVisualStyle.realistic,
      )),
    );
    expect(
      _firstAssetName(tester),
      'assets/pets/v2/realistic/adult/dog/rest/rest_01.png',
    );

    await tester.pumpWidget(
      wrap(const PetAvatar(
        mode: PetMode.happy,
        skin: PetSkin.dog,
        visualStyle: PetVisualStyle.realistic,
      )),
    );
    expect(
      _firstAssetName(tester),
      'assets/pets/v2/realistic/adult/dog/states/happy.png',
    );

    await tester.pumpWidget(
      wrap(const PetAvatar(
        mode: PetMode.excited,
        skin: PetSkin.dog,
        visualStyle: PetVisualStyle.realistic,
      )),
    );
    expect(
      _firstAssetName(tester),
      'assets/pets/v2/realistic/adult/dog/states/excited.png',
    );

    await tester.pumpWidget(
      wrap(const PetAvatar(
        mode: PetMode.listening,
        skin: PetSkin.dog,
        visualStyle: PetVisualStyle.realistic,
      )),
    );
    expect(
      _firstAssetName(tester),
      'assets/pets/v2/realistic/adult/dog/listening/listening.png',
    );
  });

  testWidgets('guineaPig talking 只有 3 frame，連續動畫超過 3 張不會 crash',
      (tester) async {
    await tester.pumpWidget(
      wrap(const PetAvatar(mode: PetMode.talking, skin: PetSkin.guineaPig)),
    );
    // 推進超過 3 個 talk frame 週期（CR-0093 放慢後）。
    for (var i = 0; i < 6; i++) {
      await tester.pump(kTalkFrameDuration);
    }
    expect(tester.takeException(), isNull);
    expect(
      _firstAssetName(tester),
      startsWith('assets/pets/talk/guinea_pig_talk_'),
    );
  });

  testWidgets('listening 依 skin 取對應圖', (tester) async {
    await tester.pumpWidget(
      wrap(const PetAvatar(mode: PetMode.listening, skin: PetSkin.fox)),
    );
    expect(_firstAssetName(tester), 'assets/pets/listening/fox_listening.png');
  });

  testWidgets('CR-0093 rest 動畫 ping-pong 播放、停在 rest frame、不 crash',
      (tester) async {
    await tester.pumpWidget(
      wrap(const PetAvatar(mode: PetMode.rest, skin: PetSkin.dog)),
    );
    // 起始為第一張 rest frame。
    expect(_firstAssetName(tester), 'assets/pets/rest/dog_rest_01.png');
    // 推進多個 rest frame 週期，全程不 crash、且都還在 rest frames 內。
    for (var i = 0; i < 8; i++) {
      await tester.pump(kRestFrameDuration);
      expect(tester.takeException(), isNull);
      expect(_firstAssetName(tester), startsWith('assets/pets/rest/dog_rest_'));
    }
  });

  group('CR-0093 pingPongFrameIndex（通用 1~4 張，不讓尾張直接跳回首張）', () {
    List<int> seq(int n, int count) =>
        [for (var i = 0; i < count; i++) pingPongFrameIndex(i, n)];

    test('N=1 → 一律 0', () {
      expect(seq(1, 5), [0, 0, 0, 0, 0]);
    });
    test('N=2 → 0,1,0,1…', () {
      expect(seq(2, 5), [0, 1, 0, 1, 0]);
    });
    test('N=3 → 0,1,2,1,0,1,2,1（rest_01→02→03→02→01…）', () {
      expect(seq(3, 8), [0, 1, 2, 1, 0, 1, 2, 1]);
    });
    test('N=4 → 0,1,2,3,2,1,0,1…', () {
      expect(seq(4, 8), [0, 1, 2, 3, 2, 1, 0, 1]);
    });
    test('N=3：最後一張(2)之後是 1，不直接跳回 0', () {
      for (var i = 0; i < 20; i++) {
        if (pingPongFrameIndex(i, 3) == 2) {
          expect(pingPongFrameIndex(i + 1, 3), 1,
              reason: 'rest_03 後應回 rest_02，不跳回 rest_01');
        }
      }
    });
  });
}
