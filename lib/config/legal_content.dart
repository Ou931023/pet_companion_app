/// 法遵文件的內文（隱私權政策、服務條款）與知情同意重點說明。
///
/// 內容刻意用長者看得懂的白話，不放工程術語。文字可在 App 內捲動完整閱讀，
/// 不只依賴外部連結（符合上架對「App 內可閱讀政策」的要求）。
///
/// 注意：這份內文屬於產品 / 法務文案範疇，正式上架前應由負責人 / 法務再校稿，
/// 並與正式 hosted 版本一致。這裡先提供完整、可閱讀、可同意的版本。
library;

/// 一段法遵文件的章節：標題 + 多個段落。
class LegalSection {
  const LegalSection({required this.heading, required this.paragraphs});

  final String heading;
  final List<String> paragraphs;
}

/// 知情同意畫面上「條列重點」的單張說明卡。
class ConsentHighlight {
  const ConsentHighlight({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;
}

/// 集中存放所有法遵文案。
class LegalContent {
  const LegalContent._();

  /// 知情同意畫面最上方的開場說明。
  static const String consentIntro = '在開始使用之前，想先讓你了解這個 App 會怎麼陪伴你、會用到哪些功能，'
      '以及我們會怎麼保護你的資料。請放心慢慢看，看完覺得可以，再按下方的「我同意」。';

  /// 知情同意畫面的重點條列（涵蓋麥克風、通知、對話蒐集、第三方 AI 等）。
  static const List<ConsentHighlight> consentHighlights = [
    ConsentHighlight(
      title: '用聲音陪你聊天（麥克風）',
      description: '你可以對著手機說話，AI 寵物會聽你說、陪你聊。只有在你開始說話時才會用到麥克風，'
          '沒有說話時不會錄音。',
    ),
    ConsentHighlight(
      title: '溫柔的提醒（通知）',
      description: '我們會用通知提醒你喝水、吃藥、簽到這些小事。如果你的狀況需要多一點關心，'
          '也會通知你授權的家人或照護人員。',
    ),
    ConsentHighlight(
      title: '記得你說過的事（對話與記憶）',
      description: '為了像老朋友一樣記得你，App 會保存你和寵物的對話，並整理成長期記憶。'
          '這些紀錄你都可以隨時查看或刪除。',
    ),
    ConsentHighlight(
      title: '幫我們知道陪伴有沒有真的幫上忙（使用紀錄）',
      description: 'App 會記錄你使用陪伴功能的次數和時間，例如開始聊天、和寵物互動、完成提醒或小遊戲。'
          '這些紀錄會用來改善 App、整理照護人員看得懂的統計，不會拿去賣給別人或做廣告追蹤。',
    ),
    ConsentHighlight(
      title: '讓寵物更聰明（第三方 AI 服務）',
      description: '你的語音和文字會交給 OpenAI 這個 AI 服務幫忙理解與回覆。'
          '我們只會傳送陪伴對話所需的內容，不會多傳不相關的資料。',
    ),
    ConsentHighlight(
      title: '溫和的關心提醒（Care Alert）',
      description: '如果系統發現你最近比較孤單、睡不好或不太舒服，會整理成提醒給照護人員參考。'
          '這只是「請多關心一下」的提醒，不是醫療診斷。',
    ),
    ConsentHighlight(
      title: '你的資料，你作主',
      description: '你隨時可以在設定裡查看或刪除記憶、申請刪除帳號。照護人員也只能看到'
          '你授權範圍內的資訊。',
    ),
  ];

  /// 同意按鈕旁的勾選說明（必須由使用者主動勾選，不預設）。
  static const String consentCheckboxLabel = '我已閱讀並了解上面的說明，也同意隱私權政策與服務條款。';

  /// 不同意時的白話說明。
  static const String consentDeclineNote = '這些功能是陪伴你所必需的，如果暫時不想同意，可以先關閉 App，'
      '等準備好了再隨時回來。';

  /// 隱私權政策內文。
  static const String privacyPolicyTitle = '隱私權政策';

  static const List<LegalSection> privacyPolicySections = [
    LegalSection(
      heading: '我們珍惜你的信任',
      paragraphs: [
        '這個 App 是用來陪伴你的。為了陪你聊天、記得你、在需要時請人多關心你，'
            '我們會用到一些你的資料。這份說明會用白話告訴你，我們會收集什麼、'
            '怎麼使用、怎麼保護。',
      ],
    ),
    LegalSection(
      heading: '我們會收集哪些資料',
      paragraphs: [
        '帳號資料：例如你的暱稱、Email，用來讓你登入、保存你的專屬寵物與紀錄。',
        '對話內容：你和 AI 寵物說的話，以及整理出來的長期記憶。',
        '聲音：你說話時的語音，用來即時聽懂你的意思。',
        '狀態線索：例如你提到的心情、睡眠、食慾等，用來判斷是否需要多一點關心。',
        '使用紀錄：例如 App 開啟與使用時間、語音或打字互動次數、寵物互動、提醒與任務完成、照片驗證、小遊戲開始與完成等。',
        '你主動填寫的資料：例如家人或照護人員的聯絡方式。',
      ],
    ),
    LegalSection(
      heading: '我們怎麼使用這些資料',
      paragraphs: [
        '讓 AI 寵物能即時聽懂你、自然地陪你聊天。',
        '記得你說過的重要事情，下次聊天時更貼心。',
        '在你狀況需要關心時，提醒你授權的家人或照護人員。',
        '了解哪些陪伴功能常被使用、互動是否增加、提醒或小遊戲是否完成，讓照護人員與管理者能看到整體使用狀況。',
        '我們不會把你的資料拿去賣給別人，也不會用於和陪伴無關的廣告。',
      ],
    ),
    LegalSection(
      heading: '第三方 AI 服務',
      paragraphs: [
        '為了讓寵物聽得懂、回得好，你的語音與文字會傳送給我們合作的 AI 服務'
            '（OpenAI）協助處理。我們只會傳送陪伴對話所需的內容。',
        '這些服務有自己的資料保護規範，我們也會盡力只在必要範圍內使用。',
      ],
    ),
    LegalSection(
      heading: '你的權利',
      paragraphs: [
        '你可以隨時在設定裡查看 App 記得了哪些事，也可以刪除不想保留的記憶。',
        '你可以申請刪除整個帳號與相關資料。',
        '照護人員或家人只能看到你授權範圍內的資訊，不會看到全部對話原文。',
      ],
    ),
    LegalSection(
      heading: '資料安全與保存',
      paragraphs: [
        '我們會用合理的技術與管理方式保護你的資料，避免外洩或被不當使用。',
        '當資料不再需要，或你要求刪除時，我們會在合理時間內處理。',
      ],
    ),
    LegalSection(
      heading: '聯絡我們',
      paragraphs: [
        '如果你對隱私有任何疑問，或想行使上面的權利，可以透過 App 內的支援管道'
            '或客服信箱與我們聯絡。',
      ],
    ),
  ];

  /// 服務條款內文。
  static const String termsOfServiceTitle = '服務條款';

  static const List<LegalSection> termsOfServiceSections = [
    LegalSection(
      heading: '關於這個服務',
      paragraphs: [
        '這個 App 提供 AI 寵物陪伴、語音聊天、長期記憶與關心提醒等功能，'
            '目的是陪伴你、並在需要時協助照護人員多關心你。',
      ],
    ),
    LegalSection(
      heading: '陪伴提醒不是醫療診斷',
      paragraphs: [
        'AI 寵物和系統的關心提醒，是陪伴與提醒，不能取代醫師、護理師或專業照護。',
        '如果你身體不舒服或遇到緊急狀況，請直接尋求家人、照護人員或醫療協助，'
            '不要只依賴 App。',
      ],
    ),
    LegalSection(
      heading: '請好好使用',
      paragraphs: [
        '請以正常、善意的方式使用這個陪伴服務。',
        '請不要用它從事違法、傷害自己或他人的行為。',
      ],
    ),
    LegalSection(
      heading: '帳號與資料',
      paragraphs: [
        '請妥善保管你的登入方式，你的寵物與紀錄都和你的帳號綁在一起。',
        '你可以隨時登出、刪除記憶，或申請刪除帳號。',
      ],
    ),
    LegalSection(
      heading: '服務的調整',
      paragraphs: [
        '為了讓陪伴更好，我們可能會更新或調整功能。',
        '如果條款有重要變動，我們會在 App 內再請你看過並同意一次。',
      ],
    ),
  ];
}
