import '../config/app_config.dart';

class UserProfile {
  const UserProfile({
    required this.hasCompletedOnboarding,
    required this.petName,
    required this.userCoins,
    required this.petBond,
    required this.petFullness,
    required this.petMood,
    required this.checkInDate,
    required this.taskCompletionState,
    required this.sttMode,
    required this.sttProxyUrl,
    required this.ttsEnabled,
    required this.fontScale,
    required this.petVolume,
    required this.speechStyle,
    required this.contentPreferences,
    required this.voiceLanguageMode,
    required this.manualAsrStrategy,
  });

  final bool hasCompletedOnboarding;
  final String petName;
  final int userCoins;
  final int petBond;
  final int petFullness;
  final int petMood;
  final String? checkInDate;
  final Map<String, bool> taskCompletionState;
  final String sttMode;
  final String sttProxyUrl;
  final bool ttsEnabled;
  final double fontScale;
  final double petVolume;
  final String speechStyle;
  final List<String> contentPreferences;
  final String voiceLanguageMode;
  final String manualAsrStrategy;

  factory UserProfile.initial() {
    return const UserProfile(
      hasCompletedOnboarding: false,
      petName: '',
      userCoins: 100,
      petBond: 30,
      petFullness: 50,
      petMood: 60,
      checkInDate: null,
      taskCompletionState: {
        'drinkWater': false,
        'eatMeal': false,
        'moodReport': false,
        'restReminder': false,
        'dailyCheckIn': false,
      },
      sttMode: 'mock',
      sttProxyUrl: AppConfig.defaultSttProxyUrl,
      ttsEnabled: true,
      fontScale: 1.0,
      petVolume: 0.9,
      speechStyle: 'gentle',
      contentPreferences: ['story', 'healthTip', 'scamAlert'],
      voiceLanguageMode: 'defaultOpenAiRealtime',
      manualAsrStrategy: 'defaultOpenAiRealtime',
    );
  }

  UserProfile copyWith({
    bool? hasCompletedOnboarding,
    String? petName,
    int? userCoins,
    int? petBond,
    int? petFullness,
    int? petMood,
    String? checkInDate,
    Map<String, bool>? taskCompletionState,
    String? sttMode,
    String? sttProxyUrl,
    bool? ttsEnabled,
    double? fontScale,
    double? petVolume,
    String? speechStyle,
    List<String>? contentPreferences,
    String? voiceLanguageMode,
    String? manualAsrStrategy,
  }) {
    return UserProfile(
      hasCompletedOnboarding:
          hasCompletedOnboarding ?? this.hasCompletedOnboarding,
      petName: petName ?? this.petName,
      userCoins: userCoins ?? this.userCoins,
      petBond: petBond ?? this.petBond,
      petFullness: petFullness ?? this.petFullness,
      petMood: petMood ?? this.petMood,
      checkInDate: checkInDate ?? this.checkInDate,
      taskCompletionState: taskCompletionState ?? this.taskCompletionState,
      sttMode: sttMode ?? this.sttMode,
      sttProxyUrl: sttProxyUrl ?? this.sttProxyUrl,
      ttsEnabled: ttsEnabled ?? this.ttsEnabled,
      fontScale: fontScale ?? this.fontScale,
      petVolume: petVolume ?? this.petVolume,
      speechStyle: speechStyle ?? this.speechStyle,
      contentPreferences: contentPreferences ?? this.contentPreferences,
      voiceLanguageMode: voiceLanguageMode ?? this.voiceLanguageMode,
      manualAsrStrategy: manualAsrStrategy ?? this.manualAsrStrategy,
    );
  }
}
