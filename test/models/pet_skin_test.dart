import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/models/pet_skin.dart';
import 'package:pet_companion_app/models/pet_status.dart';
import 'package:pet_companion_app/models/pet_visual_profile.dart';
import 'package:pet_companion_app/utils/asset_paths.dart';

void main() {
  group('PetSkin model', () {
    test('label 為長者友善中文', () {
      expect(PetSkin.dog.label, '狗狗');
      expect(PetSkin.guineaPig.label, '天竺鼠');
      expect(PetSkin.fox.label, '狐狸');
    });

    test('storageId / assetPrefix 對應檔名前綴', () {
      expect(PetSkin.dog.assetPrefix, 'dog');
      expect(PetSkin.guineaPig.assetPrefix, 'guinea_pig');
      expect(PetSkin.fox.assetPrefix, 'fox');
      expect(PetSkin.guineaPig.storageId, 'guinea_pig');
    });

    test('unlockCost：狗狗免費、天竺鼠與狐狸需要點數', () {
      expect(PetSkin.dog.unlockCost, 0);
      expect(PetSkin.dog.ownedByDefault, isTrue);
      expect(PetSkin.guineaPig.unlockCost, greaterThan(0));
      expect(PetSkin.fox.unlockCost, greaterThan(0));
      expect(PetSkin.guineaPig.ownedByDefault, isFalse);
      expect(PetSkin.fox.ownedByDefault, isFalse);
    });

    test('fromStorageId 容錯：認不得一律回預設狗狗', () {
      expect(PetSkinX.fromStorageId('guinea_pig'), PetSkin.guineaPig);
      expect(PetSkinX.fromStorageId('fox'), PetSkin.fox);
      expect(PetSkinX.fromStorageId('dog'), PetSkin.dog);
      expect(PetSkinX.fromStorageId(null), PetSkin.dog);
      expect(PetSkinX.fromStorageId('???'), PetSkin.dog);
    });
  });

  group('AssetPaths 依 skin 產生路徑', () {
    test('storage id parser 保留顯式偏好，空值維持舊版安全預設', () {
      expect(
        PetVisualStyleX.fromStorageId(null),
        PetVisualStyle.cute,
      );
      expect(
        PetVisualStyleX.fromStorageId('cute'),
        PetVisualStyle.cute,
      );
      expect(
        PetVisualStyleX.fromStorageId('realistic'),
        PetVisualStyle.realistic,
      );
    });

    test('productionProfiles 宣告現有可上線素材組合', () {
      expect(AssetPaths.productionProfiles.length, PetSkin.values.length + 1);
      expect(
        AssetPaths.productionProfiles
            .map((profile) => (
                  skin: profile.skin,
                  visualStyle: profile.visualStyle,
                  growthStage: profile.growthStage,
                ))
            .toSet(),
        {
          for (final skin in PetSkin.values)
            (
              skin: skin,
              visualStyle: PetVisualStyle.cute,
              growthStage: PetGrowthStage.adult,
            ),
          (
            skin: PetSkin.dog,
            visualStyle: PetVisualStyle.realistic,
            growthStage: PetGrowthStage.adult,
          ),
        },
      );
      for (final profile in AssetPaths.productionProfiles) {
        expect(profile.growthStage, PetGrowthStage.adult);
        expect(profile.isProductionReady, isTrue);
        expect(profile.talkFrameCount, greaterThan(0));
        expect(profile.restFrameCount, greaterThan(0));
      }
      expect(
        AssetPaths.productionProfiles
            .where((profile) => profile.isProductionPreferred)
            .single
            .visualStyle,
        PetVisualStyle.realistic,
      );
    });

    test('visualProfile 可輸出後台 tracking 需要的偏好欄位', () {
      final metadata =
          AssetPaths.visualProfile(PetSkin.fox).toTrackingMetadata();

      expect(metadata['petType'], 'fox');
      expect(metadata['visualStyle'], 'cute');
      expect(metadata['growthStage'], 'adult');
      expect(metadata['talkFrameCount'], 6);
      expect(metadata['restFrameCount'], 3);
    });

    test('productionProfiles 內所有 talk/rest/listening/state 圖檔都存在', () {
      final modes = <PetMode>{
        PetMode.normal,
        PetMode.thinking,
        PetMode.caring,
        PetMode.concerned,
        PetMode.happy,
        PetMode.smile,
        PetMode.excited,
        PetMode.thirsty,
        PetMode.sleepy,
        PetMode.hungry,
        PetMode.sad,
      };
      final paths = <String>{};

      for (final profile in AssetPaths.productionProfiles) {
        paths.addAll(
          AssetPaths.talkingFramesForStyle(
            profile.skin,
            visualStyle: profile.visualStyle,
            growthStage: profile.growthStage,
          ),
        );
        paths.addAll(
          AssetPaths.restFramesForStyle(
            profile.skin,
            visualStyle: profile.visualStyle,
            growthStage: profile.growthStage,
          ),
        );
        paths.add(
          AssetPaths.listeningForStyle(
            profile.skin,
            visualStyle: profile.visualStyle,
            growthStage: profile.growthStage,
          ),
        );
        for (final mode in modes) {
          paths.add(
            AssetPaths.stateImageForStyle(
              profile.skin,
              mode,
              visualStyle: profile.visualStyle,
              growthStage: profile.growthStage,
            ),
          );
        }
      }

      for (final path in paths) {
        expect(File(path).existsSync(), isTrue, reason: path);
      }
    });

    test('dog：talk 6 / rest 3 / states 原檔名', () {
      expect(AssetPaths.talkingFrames(PetSkin.dog), [
        'assets/pets/talk/dog_talk_01.png',
        'assets/pets/talk/dog_talk_02.png',
        'assets/pets/talk/dog_talk_03.png',
        'assets/pets/talk/dog_talk_04.png',
        'assets/pets/talk/dog_talk_05.png',
        'assets/pets/talk/dog_talk_06.png',
      ]);
      expect(AssetPaths.restFrames(PetSkin.dog).length, 3);
      expect(AssetPaths.restFrames(PetSkin.dog).first,
          'assets/pets/rest/dog_rest_01.png');
      expect(AssetPaths.stateImage(PetSkin.dog, PetMode.normal),
          'assets/pets/states/dog_normal.png');
      expect(AssetPaths.listening(PetSkin.dog),
          'assets/pets/listening/dog_listening.png');
    });

    test('guineaPig：talk 只有 3 張', () {
      expect(AssetPaths.talkingFrames(PetSkin.guineaPig), [
        'assets/pets/talk/guinea_pig_talk_01.png',
        'assets/pets/talk/guinea_pig_talk_02.png',
        'assets/pets/talk/guinea_pig_talk_03.png',
      ]);
      expect(AssetPaths.restFrames(PetSkin.guineaPig).length, 3);
      expect(AssetPaths.stateImage(PetSkin.guineaPig, PetMode.happy),
          'assets/pets/states/guinea_pig_happy.png');
    });

    test('fox：talk 6 / states / listening', () {
      expect(AssetPaths.talkingFrames(PetSkin.fox).length, 6);
      expect(AssetPaths.talkingFrames(PetSkin.fox).last,
          'assets/pets/talk/fox_talk_06.png');
      expect(AssetPaths.stateImage(PetSkin.fox, PetMode.excited),
          'assets/pets/states/fox_excited.png');
      expect(AssetPaths.listening(PetSkin.fox),
          'assets/pets/listening/fox_listening.png');
    });

    test('共用情緒：thinking→normal、concerned→caring、smile→happy', () {
      expect(AssetPaths.stateImage(PetSkin.fox, PetMode.thinking),
          'assets/pets/states/fox_normal.png');
      expect(AssetPaths.stateImage(PetSkin.fox, PetMode.concerned),
          'assets/pets/states/fox_caring.png');
      expect(AssetPaths.stateImage(PetSkin.fox, PetMode.smile),
          'assets/pets/states/fox_happy.png');
    });

    test('v2 resolver：dog realistic adult 已有完整八個透明 state', () {
      expect(
        AssetPaths.availableVisualStyles(PetSkin.dog),
        [PetVisualStyle.realistic, PetVisualStyle.cute],
      );
      expect(
        AssetPaths.preferredVisualStyle(PetSkin.dog),
        PetVisualStyle.realistic,
      );
      expect(
        AssetPaths.stateImageForStyle(
          PetSkin.dog,
          PetMode.normal,
          visualStyle: PetVisualStyle.realistic,
        ),
        'assets/pets/v2/realistic/adult/dog/states/normal.png',
      );
      expect(
        AssetPaths.stateImageForStyle(
          PetSkin.dog,
          PetMode.happy,
          visualStyle: PetVisualStyle.realistic,
        ),
        'assets/pets/v2/realistic/adult/dog/states/happy.png',
      );
      expect(
        AssetPaths.stateImageForStyle(
          PetSkin.dog,
          PetMode.caring,
          visualStyle: PetVisualStyle.realistic,
        ),
        'assets/pets/v2/realistic/adult/dog/states/caring.png',
      );
      expect(
        AssetPaths.stateImageForStyle(
          PetSkin.dog,
          PetMode.sad,
          visualStyle: PetVisualStyle.realistic,
        ),
        'assets/pets/v2/realistic/adult/dog/states/sad.png',
      );
      expect(
        AssetPaths.stateImageForStyle(
          PetSkin.dog,
          PetMode.excited,
          visualStyle: PetVisualStyle.realistic,
        ),
        'assets/pets/v2/realistic/adult/dog/states/excited.png',
      );
      expect(
        AssetPaths.stateImageForStyle(
          PetSkin.dog,
          PetMode.hungry,
          visualStyle: PetVisualStyle.realistic,
        ),
        'assets/pets/v2/realistic/adult/dog/states/hungry.png',
      );
      expect(
        AssetPaths.stateImageForStyle(
          PetSkin.dog,
          PetMode.thirsty,
          visualStyle: PetVisualStyle.realistic,
        ),
        'assets/pets/v2/realistic/adult/dog/states/thirsty.png',
      );
      expect(
        AssetPaths.stateImageForStyle(
          PetSkin.dog,
          PetMode.sleepy,
          visualStyle: PetVisualStyle.realistic,
        ),
        'assets/pets/v2/realistic/adult/dog/states/sleepy.png',
      );
      expect(
        AssetPaths.listeningForStyle(
          PetSkin.dog,
          visualStyle: PetVisualStyle.realistic,
        ),
        'assets/pets/v2/realistic/adult/dog/listening/listening.png',
      );
      expect(
        AssetPaths.restFramesForStyle(
          PetSkin.dog,
          visualStyle: PetVisualStyle.realistic,
        ),
        [
          'assets/pets/v2/realistic/adult/dog/rest/rest_01.png',
          'assets/pets/v2/realistic/adult/dog/rest/rest_02.png',
          'assets/pets/v2/realistic/adult/dog/rest/rest_03.png',
        ],
      );
      expect(
        AssetPaths.talkingFramesForStyle(
          PetSkin.dog,
          visualStyle: PetVisualStyle.realistic,
        ),
        [
          'assets/pets/v2/realistic/adult/dog/talk/talk_01.png',
          'assets/pets/v2/realistic/adult/dog/talk/talk_02.png',
          'assets/pets/v2/realistic/adult/dog/talk/talk_03.png',
          'assets/pets/v2/realistic/adult/dog/talk/talk_04.png',
          'assets/pets/v2/realistic/adult/dog/talk/talk_05.png',
          'assets/pets/v2/realistic/adult/dog/talk/talk_06.png',
        ],
      );
    });

    test('v2 resolver：非 dog realistic 時回 v1，不顯示破圖', () {
      expect(
        AssetPaths.stateImageForStyle(
          PetSkin.fox,
          PetMode.happy,
          visualStyle: PetVisualStyle.realistic,
        ),
        'assets/pets/states/fox_happy.png',
      );
      expect(
        AssetPaths.availableVisualStyles(PetSkin.fox),
        [PetVisualStyle.cute],
      );
      expect(
        AssetPaths.listeningForStyle(
          PetSkin.fox,
          visualStyle: PetVisualStyle.realistic,
        ),
        'assets/pets/listening/fox_listening.png',
      );
      expect(
        AssetPaths.restFramesForStyle(
          PetSkin.fox,
          visualStyle: PetVisualStyle.realistic,
        ).first,
        'assets/pets/rest/fox_rest_01.png',
      );
      expect(
        AssetPaths.talkingFramesForStyle(
          PetSkin.fox,
          visualStyle: PetVisualStyle.realistic,
        ).first,
        'assets/pets/talk/fox_talk_01.png',
      );
    });

    test('保底圖與第一層 fallback', () {
      expect(
        AssetPaths.defaultRestImage,
        'assets/pets/v2/realistic/adult/dog/rest/rest_01.png',
      );
      expect(AssetPaths.skinRestPrimary(PetSkin.guineaPig),
          'assets/pets/rest/guinea_pig_rest_01.png');
      expect(
        AssetPaths.skinRestPrimaryForStyle(
          PetSkin.dog,
          visualStyle: PetVisualStyle.realistic,
        ),
        'assets/pets/v2/realistic/adult/dog/rest/rest_01.png',
      );
    });

    test('v2 realistic dog 圖包畫布、透明邊界與主體位置一致', () async {
      final paths = <String>{
        ...AssetPaths.talkingFramesForStyle(
          PetSkin.dog,
          visualStyle: PetVisualStyle.realistic,
        ),
        ...AssetPaths.restFramesForStyle(
          PetSkin.dog,
          visualStyle: PetVisualStyle.realistic,
        ),
        AssetPaths.listeningForStyle(
          PetSkin.dog,
          visualStyle: PetVisualStyle.realistic,
        ),
        for (final mode in PetMode.values)
          if (mode != PetMode.talking &&
              mode != PetMode.rest &&
              mode != PetMode.listening)
            AssetPaths.stateImageForStyle(
              PetSkin.dog,
              mode,
              visualStyle: PetVisualStyle.realistic,
            ),
      };

      expect(paths.length, 18);
      for (final path in paths) {
        final bounds = await _visibleBounds(path);
        expect(bounds.canvasWidth, 1024, reason: path);
        expect(bounds.canvasHeight, 1024, reason: path);
        expect(bounds.visibleHeight, inInclusiveRange(848, 850), reason: path);
        expect(bounds.centerX, closeTo(511.5, 1.0), reason: path);
        expect(bounds.centerY, closeTo(511.5, 1.0), reason: path);
        expect(bounds.minX, greaterThan(150), reason: path);
        expect(bounds.minY, greaterThan(80), reason: path);
      }
    });
  });
}

Future<
    ({
      int canvasWidth,
      int canvasHeight,
      int minX,
      int minY,
      int visibleHeight,
      double centerX,
      double centerY,
    })> _visibleBounds(String path) async {
  final codec = await ui.instantiateImageCodec(await File(path).readAsBytes());
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final canvasWidth = image.width;
  final canvasHeight = image.height;
  final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (pixels == null) throw StateError('無法讀取圖片像素：$path');

  final bytes = pixels.buffer.asUint8List();
  var minX = image.width;
  var minY = image.height;
  var maxX = -1;
  var maxY = -1;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final alpha = bytes[(y * image.width + x) * 4 + 3];
      if (alpha == 0) continue;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }
  image.dispose();
  codec.dispose();
  if (maxX < minX || maxY < minY) throw StateError('圖片沒有可見內容：$path');

  return (
    canvasWidth: canvasWidth,
    canvasHeight: canvasHeight,
    minX: minX,
    minY: minY,
    visibleHeight: maxY - minY + 1,
    centerX: (minX + maxX) / 2,
    centerY: (minY + maxY) / 2,
  );
}
