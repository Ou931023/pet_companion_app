import 'pet_status.dart';

class PetState {
  const PetState({
    required this.mode,
    required this.message,
    this.isSpeaking = false,
  });

  final PetMode mode;
  final String message;
  final bool isSpeaking;

  PetState copyWith({
    PetMode? mode,
    String? message,
    bool? isSpeaking,
  }) {
    return PetState(
      mode: mode ?? this.mode,
      message: message ?? this.message,
      isSpeaking: isSpeaking ?? this.isSpeaking,
    );
  }
}
