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
    test('productionProfiles 宣告現有素材皆為 Q版 / 成年 / 可上線素材', () {
      expect(AssetPaths.productionProfiles.length, PetSkin.values.length);
      for (final profile in AssetPaths.productionProfiles) {
        expect(profile.visualStyle, PetVisualStyle.cute);
        expect(profile.growthStage, PetGrowthStage.adult);
        expect(profile.isProductionReady, isTrue);
        expect(profile.talkFrameCount, greaterThan(0));
        expect(profile.restFrameCount, greaterThan(0));
      }
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

    test('v2 resolver：dog realistic adult 已有四個透明 state', () {
      expect(
        AssetPaths.availableVisualStyles(PetSkin.dog),
        [PetVisualStyle.cute, PetVisualStyle.realistic],
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
    });

    test('v2 resolver：缺素材或非 dog realistic 時回 v1，不顯示破圖', () {
      expect(
        AssetPaths.stateImageForStyle(
          PetSkin.dog,
          PetMode.excited,
          visualStyle: PetVisualStyle.realistic,
        ),
        'assets/pets/states/dog_excited.png',
      );
      expect(
        AssetPaths.availableVisualStyles(PetSkin.fox),
        [PetVisualStyle.cute],
      );
      expect(
        AssetPaths.stateImageForStyle(
          PetSkin.fox,
          PetMode.happy,
          visualStyle: PetVisualStyle.realistic,
        ),
        'assets/pets/states/fox_happy.png',
      );
    });

    test('保底圖與第一層 fallback', () {
      expect(AssetPaths.defaultRestImage, 'assets/pets/rest/dog_rest_01.png');
      expect(AssetPaths.skinRestPrimary(PetSkin.guineaPig),
          'assets/pets/rest/guinea_pig_rest_01.png');
    });
  });
}
