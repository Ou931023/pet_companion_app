import 'package:flutter/material.dart';

import '../config/legal_content.dart';

/// 可在 App 內完整捲動閱讀的法遵文件畫面（隱私權政策 / 服務條款共用）。
///
/// 長者友善：大標題、大內文、足夠行距，不放任何工程術語或外部依賴。
class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({
    super.key,
    required this.title,
    required this.sections,
  });

  /// 開啟隱私權政策。
  factory LegalDocumentScreen.privacyPolicy({Key? key}) => LegalDocumentScreen(
        key: key,
        title: LegalContent.privacyPolicyTitle,
        sections: LegalContent.privacyPolicySections,
      );

  /// 開啟服務條款。
  factory LegalDocumentScreen.termsOfService({Key? key}) =>
      LegalDocumentScreen(
        key: key,
        title: LegalContent.termsOfServiceTitle,
        sections: LegalContent.termsOfServiceSections,
      );

  final String title;
  final List<LegalSection> sections;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            for (final section in sections) ...[
              Text(
                section.heading,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
              for (final paragraph in section.paragraphs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    paragraph,
                    style: const TextStyle(fontSize: 18, height: 1.55),
                  ),
                ),
              const SizedBox(height: 18),
            ],
          ],
        ),
      ),
    );
  }
}
