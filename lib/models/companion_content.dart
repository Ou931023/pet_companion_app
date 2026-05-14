enum ContentType {
  story,
  nostalgicStory,
  news,
  healthTip,
  scamAlert,
  weather,
  lifeTip,
  spiritual,
}

class CompanionContentResult {
  const CompanionContentResult({
    required this.type,
    required this.message,
    required this.usedWebSearch,
    required this.highRisk,
  });

  final ContentType type;
  final String message;
  final bool usedWebSearch;
  final bool highRisk;
}
