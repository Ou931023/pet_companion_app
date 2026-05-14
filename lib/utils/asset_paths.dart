import '../models/pet_status.dart';

class AssetPaths {
  static const List<String> talkingFrames = [
    'assets/pets/talk/dog_talk_01.png',
    'assets/pets/talk/dog_talk_02.png',
    'assets/pets/talk/dog_talk_03.png',
    'assets/pets/talk/dog_talk_04.png',
    'assets/pets/talk/dog_talk_05.png',
    'assets/pets/talk/dog_talk_06.png',
  ];

  static const List<String> restFrames = [
    'assets/pets/rest/dog_rest_01.png',
    'assets/pets/rest/dog_rest_02.png',
    'assets/pets/rest/dog_rest_03.png',
  ];

  static const String listening = 'assets/pets/listening/dog_listening.png';

  static const Map<PetMode, String> staticModes = {
    PetMode.normal: 'assets/pets/states/dog_normal.png',
    PetMode.thinking: 'assets/pets/states/dog_normal.png',
    PetMode.caring: 'assets/pets/states/dog_caring.png',
    PetMode.concerned: 'assets/pets/states/dog_caring.png',
    PetMode.happy: 'assets/pets/states/dog_happy.png',
    PetMode.smile: 'assets/pets/states/dog_happy.png',
    PetMode.excited: 'assets/pets/states/dog_excited.png',
    PetMode.thirsty: 'assets/pets/states/dog_thirsty.png',
    PetMode.sleepy: 'assets/pets/states/dog_sleepy.png',
    PetMode.hungry: 'assets/pets/states/dog_hungry.png',
    PetMode.sad: 'assets/pets/states/dog_sad.png',
  };
}
