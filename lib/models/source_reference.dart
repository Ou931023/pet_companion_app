class SourceReference {
  const SourceReference({
    required this.title,
    required this.url,
    required this.siteName,
    this.publishedAt,
  });

  final String title;
  final String url;
  final String siteName;
  final String? publishedAt;

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'url': url,
      'siteName': siteName,
      'publishedAt': publishedAt,
    };
  }

  factory SourceReference.fromJson(Map<String, dynamic> json) {
    return SourceReference(
      title: json['title']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      siteName: json['siteName']?.toString() ?? '',
      publishedAt: json['publishedAt']?.toString(),
    );
  }
}
