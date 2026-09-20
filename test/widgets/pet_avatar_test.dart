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

double _motionY(WidgetTester tester) {
  final transform = tester.widget<Transform>(
    find.byKey(const ValueKey('pet-avatar-motion')),
  );
  return transform.transform.getTranslation().y;
}

Future<void> _finishImageTransition(WidgetTester tester) =>
    tester.pump(kPetImageTransitionDuration + const Duration(milliseconds: 1));

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('預設外觀為 production 首選真實版狗狗（talking）', (tester) async {
    await tester.pumpWidget(wrap(const PetAvatar(mode: PetMode.talking)));
    expect(
      _firstAssetName(tester),
      'assets/pets/v2/realistic/adult/dog/rest/rest_01.png',
    );
  });

  testWidgets('依 skin 顯示對應狀態圖（normal）', (tester) async {
    await tester.pumpWidget(
      wrap(const PetAvatar(mode: PetMode.normal, skin: PetSkin.guineaPig)),
    );
    expect(_firstAssetName(tester), 'assets/pets/states/guinea_pig_normal.png');

    await tester.pumpWidget(
      wrap(const PetAvatar(mode: PetMode.normal, skin: PetSkin.fox)),
    );
    await _finishImageTransition(tester);
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
      'assets/pets/v2/realistic/adult/dog/rest/rest_01.png',
    );

    await tester.pumpWidget(
      wrap(const PetAvatar(
        mode: PetMode.rest,
        skin: PetSkin.dog,
        visualStyle: PetVisualStyle.realistic,
      )),
    );
    await _finishImageTransition(tester);
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
    await _finishImageTransition(tester);
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
    await _finishImageTransition(tester);
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
    await _finishImageTransition(tester);
    expect(
      _firstAssetName(tester),
      'assets/pets/v2/realistic/adult/dog/listening/listening.png',
    );
  });

  testWidgets('talking 使用固定角色主圖，不再輪播全身 frame', (tester) async {
    await tester.pumpWidget(
      wrap(const PetAvatar(mode: PetMode.talking, skin: PetSkin.guineaPig)),
    );
    final initialAsset = _firstAssetName(tester);
    expect(initialAsset, 'assets/pets/rest/guinea_pig_rest_01.png');

    for (var i = 0; i < 6; i++) {
      await tester.pump(kTalkFrameDuration);
      expect(_firstAssetName(tester), initialAsset);
    }
    expect(tester.takeException(), isNull);
  });

  for (final skin in PetSkin.values) {
    testWidgets('${skin.storageId} talking 全程不讀取 full-body talk frame',
        (tester) async {
      await tester.pumpWidget(
        wrap(PetAvatar(mode: PetMode.talking, skin: skin)),
      );
      final initialAsset = _firstAssetName(tester);

      expect(initialAsset, contains('/rest/'));
      expect(initialAsset, isNot(contains('/talk/')));
      await tester.pump(kPetTalkingMotionDuration * 2);
      expect(_firstAssetName(tester), initialAsset);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('talking 保持同一張圖，但有連續說話律動', (tester) async {
    await tester.pumpWidget(wrap(const PetAvatar(mode: PetMode.talking)));
    final initialAsset = _firstAssetName(tester);
    final initialY = _motionY(tester);

    await tester.pump(kPetTalkingMotionDuration ~/ 4);

    expect(_firstAssetName(tester), initialAsset);
    expect(_motionY(tester), isNot(equals(initialY)));
  });

  testWidgets('listening 依 skin 取對應圖', (tester) async {
    await tester.pumpWidget(
      wrap(const PetAvatar(mode: PetMode.listening, skin: PetSkin.fox)),
    );
    expect(_firstAssetName(tester), 'assets/pets/listening/fox_listening.png');
  });

  testWidgets('rest 使用固定主圖搭配呼吸律動，不切換睡眠姿勢', (tester) async {
    await tester.pumpWidget(
      wrap(const PetAvatar(mode: PetMode.rest, skin: PetSkin.dog)),
    );
    final initialAsset = _firstAssetName(tester);
    expect(initialAsset, 'assets/pets/v2/realistic/adult/dog/rest/rest_01.png');
    for (var i = 0; i < 8; i++) {
      await tester.pump(kRestFrameDuration);
      expect(tester.takeException(), isNull);
      expect(_firstAssetName(tester), initialAsset);
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
