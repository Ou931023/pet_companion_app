import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/models/pet_skin.dart';
import 'package:pet_companion_app/models/pet_status.dart';
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

    test('fromStorageId 容錯：認不得一律回預設狗狗', () {
      expect(PetSkinX.fromStorageId('guinea_pig'), PetSkin.guineaPig);
      expect(PetSkinX.fromStorageId('fox'), PetSkin.fox);
      expect(PetSkinX.fromStorageId('dog'), PetSkin.dog);
      expect(PetSkinX.fromStorageId(null), PetSkin.dog);
      expect(PetSkinX.fromStorageId('???'), PetSkin.dog);
    });
  });

  group('AssetPaths 依 skin 產生路徑', () {
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

    test('保底圖與第一層 fallback', () {
      expect(AssetPaths.defaultRestImage, 'assets/pets/rest/dog_rest_01.png');
      expect(AssetPaths.skinRestPrimary(PetSkin.guineaPig),
          'assets/pets/rest/guinea_pig_rest_01.png');
    });
  });
}
