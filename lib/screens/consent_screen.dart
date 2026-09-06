import 'package:flutter/material.dart';

import '../config/legal_content.dart';
import 'legal_document_screen.dart';

/// 首次啟動的知情同意畫面。
///
/// 使用者必須主動勾選同意（不預設勾選）才能按「我同意」繼續；在此之前無法進入
/// 會蒐集資料的功能。可從這裡開啟完整的隱私權政策 / 服務條款閱讀。
class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key, required this.onAgreed});

  /// 使用者完成勾選並按下「我同意」時呼叫。
  final Future<void> Function() onAgreed;

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _agreed = false;
  bool _submitting = false;

  Future<void> _submit() async {
    if (!_agreed || _submitting) return;
    setState(() => _submitting = true);
    await widget.onAgreed();
    // onAgreed 多會讓上層 gate 重建並換頁，這裡仍保險地檢查 mounted。
    if (!mounted) return;
    setState(() => _submitting = false);
  }

  void _openPrivacyPolicy() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LegalDocumentScreen.privacyPolicy(),
      ),
    );
  }

  void _openTerms() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LegalDocumentScreen.termsOfService(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                children: [
                  const Text(
                    '歡迎來到你的陪伴空間',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    LegalContent.consentIntro,
                    style: TextStyle(fontSize: 18, height: 1.55),
                  ),
                  const SizedBox(height: 22),
                  for (final highlight in LegalContent.consentHighlights)
                    _HighlightCard(highlight: highlight),
                  const SizedBox(height: 8),
                  _LegalLinks(
                    onPrivacy: _openPrivacyPolicy,
                    onTerms: _openTerms,
                  ),
                ],
              ),
            ),
            _ConsentFooter(
              agreed: _agreed,
              submitting: _submitting,
              onChanged: (value) => setState(() => _agreed = value),
              onSubmit: _submit,
              primaryColor: theme.colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class _HighlightCard extends StatelessWidget {
  const _HighlightCard({required this.highlight});

  final ConsentHighlight highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            highlight.title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            highlight.description,
            style: const TextStyle(fontSize: 17, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _LegalLinks extends StatelessWidget {
  const _LegalLinks({required this.onPrivacy, required this.onTerms});

  final VoidCallback onPrivacy;
  final VoidCallback onTerms;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: onPrivacy,
          icon: const Icon(Icons.privacy_tip_outlined, size: 24),
          label: const Text(
            '閱讀隱私權政策',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: onTerms,
          icon: const Icon(Icons.description_outlined, size: 24),
          label: const Text(
            '閱讀服務條款',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ],
    );
  }
}

class _ConsentFooter extends StatelessWidget {
  const _ConsentFooter({
    required this.agreed,
    required this.submitting,
    required this.onChanged,
    required this.onSubmit,
    required this.primaryColor,
  });

  final bool agreed;
  final bool submitting;
  final ValueChanged<bool> onChanged;
  final VoidCallback onSubmit;
  final Color primaryColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 主動勾選，預設未勾。整列可點，方便長者操作。
          InkWell(
            onTap: () => onChanged(!agreed),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: agreed,
                    onChanged: (value) => onChanged(value ?? false),
                  ),
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        LegalContent.consentCheckboxLabel,
                        style: TextStyle(fontSize: 17, height: 1.45),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 58,
            child: FilledButton(
              onPressed: (agreed && !submitting) ? onSubmit : null,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: submitting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      '我同意，開始陪伴',
                      style:
                          TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            LegalContent.consentDeclineNote,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14.5,
              height: 1.45,
              color: Colors.black.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}
