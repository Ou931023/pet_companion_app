import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/models/pet_skin.dart';
import 'package:pet_companion_app/models/pet_status.dart';
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

  testWidgets('guineaPig talking 只有 3 frame，連續動畫超過 3 張不會 crash',
      (tester) async {
    await tester.pumpWidget(
      wrap(const PetAvatar(mode: PetMode.talking, skin: PetSkin.guineaPig)),
    );
    // 推進超過 3 個 frame 週期（220ms * 6）。
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 220));
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
}
