import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/models/pet_skin.dart';
import 'package:pet_companion_app/models/pet_status.dart';
import 'package:pet_companion_app/utils/asset_paths.dart';

/// CR-0053：新寵物「雪貂 ferret」整合測試。
/// 涵蓋換皮註冊、asset resolver 路徑、商店清單，以及實際圖檔已去背、
/// 尺寸統一（1024x1024、含 alpha）。不更動 dog / fox / guineaPig。
void main() {
  group('PetSkin：雪貂已正確註冊', () {
    test('label / assetPrefix / storageId', () {
      expect(PetSkin.ferret.label, '雪貂');
      expect(PetSkin.ferret.assetPrefix, 'ferret');
      expect(PetSkin.ferret.storageId, 'ferret');
    });

    test('需付費解鎖、非預設擁有', () {
      expect(PetSkin.ferret.unlockCost, greaterThan(0));
      expect(PetSkin.ferret.ownedByDefault, isFalse);
    });

    test('fromStorageId 可還原雪貂', () {
      expect(PetSkinX.fromStorageId('ferret'), PetSkin.ferret);
    });

    test('出現在換皮 / 商店清單（PetSkin.values）', () {
      expect(PetSkin.values, contains(PetSkin.ferret));
    });

    test('不影響既有 dog / fox / guineaPig', () {
      expect(PetSkin.dog.assetPrefix, 'dog');
      expect(PetSkin.fox.assetPrefix, 'fox');
      expect(PetSkin.guineaPig.assetPrefix, 'guinea_pig');
      expect(PetSkin.dog.ownedByDefault, isTrue);
    });
  });

  group('AssetPaths：雪貂路徑', () {
    test('rest 為 3 張', () {
      final rest = AssetPaths.restFrames(PetSkin.ferret);
      expect(rest.length, 3);
      expect(rest.first, 'assets/pets/rest/ferret_rest_01.png');
      expect(rest.last, 'assets/pets/rest/ferret_rest_03.png');
    });

    test('talk 為 6 張', () {
      final talk = AssetPaths.talkingFrames(PetSkin.ferret);
      expect(talk.length, 6);
      expect(talk.first, 'assets/pets/talk/ferret_talk_01.png');
      expect(talk.last, 'assets/pets/talk/ferret_talk_06.png');
    });

    test('listening 為單張', () {
      expect(AssetPaths.listening(PetSkin.ferret),
          'assets/pets/listening/ferret_listening.png');
    });

    test('states 八種情緒齊全', () {
      const modeToSuffix = {
        PetMode.normal: 'normal',
        PetMode.happy: 'happy',
        PetMode.sad: 'sad',
        PetMode.excited: 'excited',
        PetMode.sleepy: 'sleepy',
        PetMode.hungry: 'hungry',
        PetMode.thirsty: 'thirsty',
        PetMode.caring: 'caring',
      };
      for (final entry in modeToSuffix.entries) {
        expect(AssetPaths.stateImage(PetSkin.ferret, entry.key),
            'assets/pets/states/ferret_${entry.value}.png');
      }
    });

    test('共用情緒映射與其他外觀一致', () {
      expect(AssetPaths.stateImage(PetSkin.ferret, PetMode.thinking),
          'assets/pets/states/ferret_normal.png');
      expect(AssetPaths.stateImage(PetSkin.ferret, PetMode.concerned),
          'assets/pets/states/ferret_caring.png');
      expect(AssetPaths.stateImage(PetSkin.ferret, PetMode.smile),
          'assets/pets/states/ferret_happy.png');
    });

    test('第一層 fallback 為自己的 rest_01', () {
      expect(AssetPaths.skinRestPrimary(PetSkin.ferret),
          'assets/pets/rest/ferret_rest_01.png');
    });
  });

  group('雪貂圖檔：存在、PNG、透明、尺寸統一', () {
    // 收集雪貂所有正式素材路徑（rest 3 / listening 1 / talk 6 / states 8）。
    final paths = <String>[
      ...AssetPaths.restFrames(PetSkin.ferret),
      AssetPaths.listening(PetSkin.ferret),
      ...AssetPaths.talkingFrames(PetSkin.ferret),
      for (final suffix in [
        'normal',
        'happy',
        'sad',
        'excited',
        'sleepy',
        'hungry',
        'thirsty',
        'caring',
      ])
        'assets/pets/states/ferret_$suffix.png',
    ];

    test('共 18 張素材路徑（3+1+6+8）', () {
      expect(paths.length, 18);
    });

    for (final path in paths) {
      test('$path 存在、為 1024x1024 RGBA PNG', () {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: '$path 不存在');

        final bytes = file.readAsBytesSync();
        // PNG 簽章。
        expect(bytes.sublist(0, 8),
            [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
            reason: '$path 不是合法 PNG');

        // IHDR：width(16..19) height(20..23) bitDepth(24) colorType(25)。
        int be32(int o) =>
            (bytes[o] << 24) | (bytes[o + 1] << 16) | (bytes[o + 2] << 8) |
            bytes[o + 3];
        final width = be32(16);
        final height = be32(20);
        final colorType = bytes[25];

        expect(width, 1024, reason: '$path 寬度應為 1024');
        expect(height, 1024, reason: '$path 高度應為 1024');
        // colorType 6 = 真彩色 + alpha（去背後具透明通道）。
        expect(colorType, 6, reason: '$path 應為含 alpha 的 RGBA PNG');
      });
    }
  });
}
