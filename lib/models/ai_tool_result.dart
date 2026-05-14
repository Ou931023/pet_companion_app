import 'pet_status.dart';

class AiToolResult {
  const AiToolResult({
    required this.toolName,
    required this.success,
    required this.message,
    required this.petMode,
    required this.shouldSpeak,
    this.updatedCoins,
    this.extraData = const {},
  });

  final String toolName;
  final bool success;
  final String message;
  final PetMode petMode;
  final bool shouldSpeak;
  final int? updatedCoins;
  final Map<String, dynamic> extraData;
}
