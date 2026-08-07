import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/config/legal_config.dart';

void main() {
  group('LegalConfig store readiness', () {
    test('legal links reflect default placeholders or injected hosted values',
        () {
      final values = <String>[
        LegalConfig.privacyPolicyUrl,
        LegalConfig.termsOfServiceUrl,
        LegalConfig.supportUrl,
        LegalConfig.contactEmail,
      ];
      final placeholders = values.map(LegalConfig.isPlaceholder).toList();

      if (placeholders.every((value) => value)) {
        expect(LegalConfig.areStoreLegalLinksConfigured, isFalse);
      } else {
        expect(placeholders, everyElement(isFalse));
        expect(LegalConfig.areStoreLegalLinksConfigured, isTrue);
      }
    });

    test('placeholder detection treats blank values as placeholders', () {
      expect(LegalConfig.isPlaceholder(''), isTrue);
      expect(LegalConfig.isPlaceholder('   '), isTrue);
      expect(LegalConfig.isPlaceholder('TODO_SUPPORT_URL'), isTrue);
      expect(LegalConfig.isPlaceholder('https://example.com/privacy'), isFalse);
      expect(LegalConfig.isPlaceholder('support@example.com'), isFalse);
    });
  });
}
