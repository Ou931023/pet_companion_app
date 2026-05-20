class TaigiAsrStatus {
  const TaigiAsrStatus({
    required this.enabled,
    required this.available,
    required this.warmingUp,
    required this.modelReady,
    required this.message,
  });

  final bool enabled;
  final bool available;
  final bool warmingUp;
  final bool modelReady;
  final String message;

  String get userMessage {
    if (warmingUp) return '台語語音辨識準備中';
    if (available) return '台語語音辨識可使用';
    return '台語語音辨識暫時無法使用';
  }

  factory TaigiAsrStatus.fromJson(Map<String, dynamic> json) {
    return TaigiAsrStatus(
      enabled: json['enabled'] == true,
      available: json['available'] == true,
      warmingUp: json['warmingUp'] == true,
      modelReady: json['modelReady'] == true,
      message: json['message']?.toString() ?? '',
    );
  }

  factory TaigiAsrStatus.unavailable() {
    return const TaigiAsrStatus(
      enabled: false,
      available: false,
      warmingUp: false,
      modelReady: false,
      message: '台語語音辨識暫時無法使用',
    );
  }
}
