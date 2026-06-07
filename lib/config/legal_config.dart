/// 法遵（隱私 / 條款 / 知情同意）相關的集中設定。
///
/// 這裡只放「常數」與「版本號」，實際條款內文放在 [legal_content.dart]。
/// 對外連結目前先放 TODO 佔位字串，等正式 hosted 頁面上線後再填入真實網址，
/// **不要在這裡捏造看似真實的網址**，避免長者點到不存在的頁面。
class LegalConfig {
  const LegalConfig._();

  /// 目前條款 / 同意內容的版本號。
  ///
  /// 只要隱私權政策、服務條款或資料蒐集說明有實質變動，就把這個版本號往上加，
  /// 已同意舊版本的使用者下次啟動時會被要求重新閱讀並同意新版本。
  static const String consentVersion = '2026-06-01.v1';

  /// 隱私權政策正式 hosted 頁面網址（上架時填入）。
  ///
  /// TODO(上架前)：替換成正式公開的隱私權政策網址，例如機構官網的政策頁。
  static const String privacyPolicyUrl = 'TODO_PRIVACY_POLICY_URL';

  /// 服務條款正式 hosted 頁面網址（上架時填入）。
  ///
  /// TODO(上架前)：替換成正式公開的服務條款網址。
  static const String termsOfServiceUrl = 'TODO_TERMS_OF_SERVICE_URL';

  /// 技術支援 / 客服說明頁網址（上架時填入）。
  ///
  /// TODO(上架前)：替換成正式的支援頁面網址。
  static const String supportUrl = 'TODO_SUPPORT_URL';

  /// 聯絡信箱（上架時填入正式客服信箱）。
  ///
  /// TODO(上架前)：替換成正式的聯絡 / 客服信箱。
  static const String contactEmail = 'TODO_CONTACT_EMAIL';

  /// 判斷上面的 URL / Email 是否仍是未填入的佔位字串。
  /// UI 可用它決定是否顯示「在瀏覽器開啟」這類外部連結入口（避免點到 TODO）。
  static bool isPlaceholder(String value) =>
      value.isEmpty || value.startsWith('TODO');
}
