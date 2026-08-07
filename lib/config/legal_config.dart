/// 法遵（隱私 / 條款 / 知情同意）相關的集中設定。
///
/// 這裡只放「常數」與「版本號」，實際條款內文放在 [legal_content.dart]。
/// 對外連結由 `--dart-define` 注入，等正式 hosted 頁面上線後填入真實網址。
/// **不要捏造看似真實的網址**，避免長者點到不存在的頁面。
class LegalConfig {
  const LegalConfig._();

  /// 目前條款 / 同意內容的版本號。
  ///
  /// 只要隱私權政策、服務條款或資料蒐集說明有實質變動，就把這個版本號往上加，
  /// 已同意舊版本的使用者下次啟動時會被要求重新閱讀並同意新版本。
  static const String consentVersion = '2026-08-07.v1';

  /// 隱私權政策正式 hosted 頁面網址（上架時填入）。
  ///
  /// 由 `--dart-define=PRIVACY_POLICY_URL=https://...` 注入。
  static const String privacyPolicyUrl = String.fromEnvironment(
    'PRIVACY_POLICY_URL',
    defaultValue: 'TODO_PRIVACY_POLICY_URL',
  );

  /// 服務條款正式 hosted 頁面網址（上架時填入）。
  ///
  /// 由 `--dart-define=TERMS_OF_SERVICE_URL=https://...` 注入。
  static const String termsOfServiceUrl = String.fromEnvironment(
    'TERMS_OF_SERVICE_URL',
    defaultValue: 'TODO_TERMS_OF_SERVICE_URL',
  );

  /// 技術支援 / 客服說明頁網址（上架時填入）。
  ///
  /// 由 `--dart-define=SUPPORT_URL=https://...` 注入。
  static const String supportUrl = String.fromEnvironment(
    'SUPPORT_URL',
    defaultValue: 'TODO_SUPPORT_URL',
  );

  /// 聯絡信箱（上架時填入正式客服信箱）。
  ///
  /// 由 `--dart-define=CONTACT_EMAIL=support@example.com` 注入。
  static const String contactEmail = String.fromEnvironment(
    'CONTACT_EMAIL',
    defaultValue: 'TODO_CONTACT_EMAIL',
  );

  /// 判斷上面的 URL / Email 是否仍是未填入的佔位字串。
  /// UI 可用它決定是否顯示「在瀏覽器開啟」這類外部連結入口（避免點到 TODO）。
  static bool isPlaceholder(String value) =>
      value.trim().isEmpty || value.trim().startsWith('TODO');

  static bool get areStoreLegalLinksConfigured =>
      !isPlaceholder(privacyPolicyUrl) &&
      !isPlaceholder(termsOfServiceUrl) &&
      !isPlaceholder(supportUrl) &&
      !isPlaceholder(contactEmail);
}
