class SourceReference {
  const SourceReference({
    required this.title,
    required this.url,
    required this.siteName,
    this.domain = '',
    this.summary = '',
    this.publishedAt,
  });

  final String title;
  final String url;
  final String siteName;
  final String domain;
  final String summary;
  final String? publishedAt;

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'url': url,
      'siteName': siteName,
      'domain': domain,
      'summary': summary,
      'publishedAt': publishedAt,
    };
  }

  factory SourceReference.fromJson(Map<String, dynamic> json) {
    return SourceReference(
      title: json['title']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      siteName:
          json['siteName']?.toString() ?? json['domain']?.toString() ?? '',
      domain: json['domain']?.toString() ?? '',
      summary: json['summary']?.toString() ?? '',
      publishedAt: json['publishedAt']?.toString(),
    );
  }
}
