import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/models/pet_skin.dart';
import 'package:pet_companion_app/models/pet_status.dart';
import 'package:pet_companion_app/utils/asset_paths.dart';

/// CR-0088：新寵物「麻吉 mochi」整合 + 全寵物 8 狀態可解析測試。
/// 不更動 dog / fox / guineaPig / ferret。
void main() {
  group('PetSkin：麻吉已正確註冊', () {
    test('label / assetPrefix / storageId', () {
      expect(PetSkin.mochi.label, '麻吉');
      expect(PetSkin.mochi.assetPrefix, 'mochi');
      expect(PetSkin.mochi.storageId, 'mochi');
    });

    test('fromStorageId 可還原麻吉', () {
      expect(PetSkinX.fromStorageId('mochi'), PetSkin.mochi);
    });

    test('出現在換皮 / 商店清單（PetSkin.values），排在 ferret 之後', () {
      expect(PetSkin.values, contains(PetSkin.mochi));
      expect(PetSkin.values.last, PetSkin.mochi);
    });

    test('不影響既有 dog / fox / guineaPig / ferret', () {
      expect(PetSkin.dog.assetPrefix, 'dog');
      expect(PetSkin.fox.assetPrefix, 'fox');
      expect(PetSkin.guineaPig.assetPrefix, 'guinea_pig');
      expect(PetSkin.ferret.assetPrefix, 'ferret');
    });
  });

  group('AssetPaths：麻吉路徑', () {
    test('rest 3 / talk 6 / listening 1', () {
      expect(AssetPaths.restFrames(PetSkin.mochi).length, 3);
      expect(AssetPaths.talkingFrames(PetSkin.mochi).length, 6);
      expect(AssetPaths.restFrames(PetSkin.mochi).first,
          'assets/pets/rest/mochi_rest_01.png');
      expect(AssetPaths.talkingFrames(PetSkin.mochi).last,
          'assets/pets/talk/mochi_talk_06.png');
      expect(AssetPaths.listening(PetSkin.mochi),
          'assets/pets/listening/mochi_listening.png');
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
        expect(AssetPaths.stateImage(PetSkin.mochi, entry.key),
            'assets/pets/states/mochi_${entry.value}.png');
      }
    });
  });

  group('全寵物：每隻都能取得 8 種基本狀態（含 fallback 不崩潰）', () {
    const states = [
      PetMode.normal,
      PetMode.happy,
      PetMode.sad,
      PetMode.excited,
      PetMode.sleepy,
      PetMode.hungry,
      PetMode.thirsty,
      PetMode.caring,
    ];
    for (final skin in PetSkin.values) {
      test('${skin.assetPrefix} 8 狀態路徑都解析得到', () {
        for (final mode in states) {
          final path = AssetPaths.stateImage(skin, mode);
          expect(path, startsWith('assets/pets/states/${skin.assetPrefix}_'));
          expect(path, endsWith('.png'));
        }
      });
    }
  });

  group('麻吉圖檔：存在、1024² RGBA、透明背景（去背後）', () {
    final paths = <String>[
      ...AssetPaths.restFrames(PetSkin.mochi),
      AssetPaths.listening(PetSkin.mochi),
      ...AssetPaths.talkingFrames(PetSkin.mochi),
      for (final s in [
        'normal',
        'happy',
        'sad',
        'excited',
        'sleepy',
        'hungry',
        'thirsty',
        'caring',
      ])
        'assets/pets/states/mochi_$s.png',
    ];

    test('共 18 張素材路徑（3+1+6+8）', () {
      expect(paths.length, 18);
    });

    for (final path in paths) {
      test('$path 存在、為 1024x1024 RGBA PNG', () {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: '$path 不存在');
        final bytes = file.readAsBytesSync();
        expect(bytes.sublist(0, 8),
            [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
            reason: '$path 不是合法 PNG');
        int be32(int o) =>
            (bytes[o] << 24) | (bytes[o + 1] << 16) | (bytes[o + 2] << 8) |
            bytes[o + 3];
        expect(be32(16), 1024, reason: '$path 寬度應為 1024');
        expect(be32(20), 1024, reason: '$path 高度應為 1024');
        expect(bytes[25], 6, reason: '$path 應為含 alpha 的 RGBA PNG');
      });
    }
  });

  test('pubspec 已註冊正式素材資料夾', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final dir in [
      'assets/pets/rest/',
      'assets/pets/listening/',
      'assets/pets/talk/',
      'assets/pets/states/',
    ]) {
      expect(pubspec.contains(dir), isTrue, reason: 'pubspec 缺 $dir');
    }
  });
}
