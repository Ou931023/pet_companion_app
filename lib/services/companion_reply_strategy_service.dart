import '../models/companion_reply.dart';
import '../models/language_route.dart';

class CompanionReplyStrategyService {
  const CompanionReplyStrategyService();

  CompanionReplyPlan buildPlan(CompanionContext context) {
    final emotion = _normalizeEmotion(context.fusedEmotion);
    final state = _stateFromContext(context);
    final lowMood = _isLowMood(emotion, context.userText, state);
    final action = context.suggestedAction.trim();
    final optionalSuggestion =
        lowMood ? '' : _oneSentence(context.optionalSuggestion.trim());

    return CompanionReplyPlan(
      emotionalAck: _emotionalAck(
        emotion: emotion,
        userText: context.userText,
        petName: context.petName,
        action: action,
        state: state,
        replyLanguage: context.replyLanguage,
      ),
      careQuestion: _careQuestion(
        emotion,
        context.userText,
        state,
        context.replyLanguage,
      ),
      continuationPrompt: _continuationPrompt(
        emotion: emotion,
        action: action,
        replyLanguage: context.replyLanguage,
      ),
      optionalSuggestion: optionalSuggestion,
      petExpression: _petExpression(emotion, action, state),
      petAction: _petAction(emotion, action, state),
      companionMode: _companionMode(emotion, action, state),
    );
  }

  String buildReply(CompanionContext context) {
    return compose(buildPlan(context));
  }

  CompanionReplyDebugInfo debugInfo(CompanionContext context) {
    final plan = buildPlan(context);
    final state = _stateFromContext(context);
    return CompanionReplyDebugInfo(
      detectedEmotion: context.detectedEmotion,
      fusedEmotion: context.fusedEmotion,
      companionMode: plan.companionMode,
      petExpression: plan.petExpression,
      petAction: plan.petAction,
      userStateHints: state,
      referencedPreviousState: _referencesPreviousState(plan.emotionalAck),
      optionalSuggestionDeferred:
          context.optionalSuggestion.trim().isNotEmpty &&
              plan.optionalSuggestion.trim().isEmpty,
    );
  }

  String compose(CompanionReplyPlan plan) {
    final parts = <String>[
      plan.emotionalAck,
      if (plan.careQuestion.isNotEmpty) plan.careQuestion,
      if (plan.careQuestion.isEmpty && plan.continuationPrompt.isNotEmpty)
        plan.continuationPrompt,
      if (plan.optionalSuggestion.isNotEmpty) plan.optionalSuggestion,
    ];
    return _limitToOneQuestion(parts
        .where((part) => part.trim().isNotEmpty)
        .map((part) => part.trim())
        .join(' '));
  }

  String _emotionalAck({
    required String emotion,
    required String userText,
    required String petName,
    required String action,
    required UserStateHints state,
    required ReplyLanguage replyLanguage,
  }) {
    final followup = _followupAck(userText, petName, state, replyLanguage);
    if (followup.isNotEmpty) return followup;
    if (_usesTaigiVoice(replyLanguage)) {
      return _taigiEmotionalAck(
        emotion: emotion,
        userText: userText,
        petName: petName,
        action: action,
      );
    }
    if (userText.contains('家裡好安靜') || userText.contains('沒有人陪')) {
      return _variation(
        'lonely',
        userText,
        [
          '聽起來今天有點安靜，$petName靠近你一點。',
          '家裡安靜下來時，心裡也會空空的，我陪你待一下。',
          '沒有人陪的感覺不太好受，我在你旁邊。',
        ],
      );
    }
    if (userText.contains('不太想吃飯')) {
      return _variation(
        'lowAppetite',
        userText,
        [
          '聽起來你今天胃口不太好，我先陪你慢慢來。',
          '吃不太下的時候會有點辛苦，我在旁邊陪你。',
          '今天身體好像不太想吃東西，我先不催你。',
        ],
      );
    }
    if (userText.contains('睡不好') || userText.contains('睡不著')) {
      return _variation(
        'poorSleep',
        userText,
        [
          '睡不好真的會讓人很累，我在旁邊陪你慢慢安定下來。',
          '一整晚沒睡穩很不好受，我陪你放慢一點。',
          '睡得不踏實的感覺我聽見了，我陪你先緩一緩。',
        ],
      );
    }
    return switch (emotion) {
      'lonely' => _variation('lonely', userText, [
          '聽起來你有點孤單，$petName在這裡陪你。',
          '這種沒人靠近的感覺，我會陪你一起待著。',
          '我聽見你想有人陪，先讓我陪你一下。',
        ]),
      'sad' => _variation('sad', userText, [
          '我聽得出來你心裡有點低落，我先陪著你。',
          '今天心裡好像不太輕鬆，我陪你慢慢說。',
          '難受的時候不用急著變好，我陪你待一會兒。',
        ]),
      'tired' => _variation('tired', userText, [
          '聽起來你有點累了，我陪你慢慢說。',
          '今天好像耗了不少力氣，我陪你休息一下。',
          '累的時候先不用勉強，我在旁邊陪你。',
        ]),
      'anxious' => _variation('anxious', userText, [
          '聽起來你有些不安，我在這裡陪你穩一下。',
          '心裡緊緊的時候很辛苦，我陪你慢慢放鬆。',
          '我聽見你有點擔心，先讓我陪你停一下。',
        ]),
      'happy' => '聽起來你心情不錯，$petName也替你開心。',
      _ => _neutralAck(action, petName),
    };
  }

  String _followupAck(
    String userText,
    String petName,
    UserStateHints state,
    ReplyLanguage replyLanguage,
  ) {
    if (_usesTaigiVoice(replyLanguage)) {
      if (state.mentionedPoorSleep &&
          _containsAny(userText, ['累', '疲倦', '沒精神', '袂好睏'])) {
        return '袂好睏真的會足累，我佇遮陪你慢慢放鬆。';
      }
      if (state.mentionedLonely &&
          _containsAny(userText, ['沒什麼人陪', '沒有人陪', '沒人陪', '足安靜'])) {
        return '頭前彼份安靜我有聽著，這馬若感覺無人陪，我靠近你一點。';
      }
    }
    if (state.mentionedPoorSleep &&
        _containsAny(userText, ['累', '疲倦', '沒精神'])) {
      return '你剛剛也說睡得不太好，難怪現在會覺得累。我陪你慢慢休息一下。';
    }
    if (state.mentionedLonely &&
        _containsAny(userText, ['沒什麼人陪', '沒有人陪', '沒人陪'])) {
      return '剛剛那份安靜好像還在，現在又覺得沒什麼人陪，我靠近你一點。';
    }
    if (state.mentionedLowAppetite && _containsAny(userText, ['累', '不舒服'])) {
      return '你前面提到胃口不太好，現在又覺得不舒服，我先陪你慢慢緩一下。';
    }
    if (state.mentionedPainOrDiscomfort &&
        _containsAny(userText, ['累', '睡不好'])) {
      return '剛剛的不舒服我有記著，現在先別急，我陪你慢慢說。';
    }
    return '';
  }

  String _taigiEmotionalAck({
    required String emotion,
    required String userText,
    required String petName,
    required String action,
  }) {
    if (_containsAny(userText, ['今仔日', '厝內', '足安靜', '家裡好安靜'])) {
      return _variation('taigiLonely', userText, [
        '聽起來今仔日有一點孤單齁，$petName佇遮陪你。',
        '厝內安靜落來，心肝嘛會空空的，我佇你身邊。',
        '今仔日若感覺足安靜，我靠近你一點，陪你慢慢講。',
      ]);
    }
    if (_containsAny(userText, ['袂好睏', '睡不好', '睡不著', '睏袂好'])) {
      return _variation('taigiPoorSleep', userText, [
        '袂好睏真的會足累，我陪你慢慢放鬆一下。',
        '睏袂好真歹受，我佇遮陪你先緩一下。',
        '一暝無睏好，身體會足無力，我陪你慢慢安定。',
      ]);
    }
    if (_containsAny(userText, ['不太想吃飯', '沒胃口', '吃不下'])) {
      return '食袂落會有淡薄仔辛苦，我先陪你慢慢來。';
    }
    return switch (emotion) {
      'lonely' => '聽起來你有淡薄仔孤單，$petName佇遮陪你。',
      'sad' => '我聽有你心情無爽快，我陪你慢慢講。',
      'tired' => '聽起來你足累，我陪你先歇一下。',
      'anxious' => '心內若緊緊，我佇遮陪你慢慢穩落來。',
      'happy' => '聽起來你心情袂䆀，$petName嘛替你歡喜。',
      _ => _neutralAck(action, petName, ReplyLanguage.mixedZhTaigi),
    };
  }

  String _neutralAck(
    String action,
    String petName, [
    ReplyLanguage replyLanguage = ReplyLanguage.zhTw,
  ]) {
    if (_usesTaigiVoice(replyLanguage)) {
      return switch (action) {
        'story' => '好呀，$petName陪你聽一小段故事，咱慢慢聽。',
        'news' || 'search' => '好呀，我陪你看可信的資料，簡單講予你聽。',
        'reminder' => '好，我先陪你共這件代誌記牢牢。',
        'task' => '好，咱做一點點就好，免著急。',
        _ => '嗯嗯，我佇遮陪你聽著。',
      };
    }
    return switch (action) {
      'story' => '好呀，$petName陪你聽一小段故事。',
      'news' || 'search' => '好呀，我陪你看看可信的資料。',
      'reminder' => '好，我先陪你把這件事記穩。',
      'task' => '好，我陪你一起把這件事完成。',
      _ => '嗯嗯，我在這裡陪你聽著。',
    };
  }

  String _careQuestion(
    String emotion,
    String userText,
    UserStateHints state,
    ReplyLanguage replyLanguage,
  ) {
    if (_usesTaigiVoice(replyLanguage)) {
      if (_containsAny(userText, ['袂好睏', '睡不好', '睡不著', '睏袂好'])) {
        return '你是較難入睡，還是睏到一半會醒來？';
      }
      if (_containsAny(userText, ['不太想吃飯', '沒胃口', '吃不下'])) {
        return '你今仔日有食一點物件矣無？';
      }
      if (_isLowMood(emotion, userText, state)) {
        return '你欲毋欲佮我講幾句話？';
      }
    }
    if (_containsAny(userText, ['不太想吃飯', '沒胃口', '吃不下'])) {
      return '那我想先關心你一下，你今天有吃一點東西嗎？';
    }
    if (state.mentionedPoorSleep && _containsAny(userText, ['累', '疲倦'])) {
      return '你想先陪我安靜休息一下嗎？';
    }
    if (_isLowMood(emotion, userText, state)) {
      return '你想慢慢跟我說說嗎？';
    }
    return '';
  }

  String _continuationPrompt({
    required String emotion,
    required String action,
    required ReplyLanguage replyLanguage,
  }) {
    if (_usesTaigiVoice(replyLanguage)) {
      if (action == 'story') return '我會講短短，陪你輕鬆聽。';
      if (action == 'news' || action == 'search') {
        return '我會簡單整理，無來源的我袂亂講。';
      }
      if (action == 'reminder') return '我會用簡單的方式提醒你。';
      if (action == 'task') return '做一點點嘛真好。';
      if (emotion == 'happy') return '咱共這份好心情留較久一點。';
      return '咱慢慢講就好。';
    }
    if (action == 'story') return '我會講短一點，陪你輕鬆聽。';
    if (action == 'news' || action == 'search') {
      return '我會簡短整理，不亂說沒有來源的內容。';
    }
    if (action == 'reminder') return '我會用簡單的方式提醒你。';
    if (action == 'task') return '完成一點點也很好。';
    if (emotion == 'happy') return '我們可以把這份好心情留久一點。';
    return '我們慢慢聊就好。';
  }

  String _petExpression(String emotion, String action, UserStateHints state) {
    if (action == 'story' || action == 'news' || action == 'search') {
      return 'calm';
    }
    if (state.mentionedPoorSleep || state.mentionedTired) return 'sleepy';
    return switch (emotion) {
      'happy' => 'happy',
      'tired' => 'sleepy',
      'sad' || 'lonely' || 'anxious' => 'concerned',
      _ => 'idle',
    };
  }

  String _petAction(String emotion, String action, UserStateHints state) {
    if (action == 'task' || action == 'reminder') return 'nod';
    if (state.mentionedPoorSleep || state.mentionedTired) return 'rest';
    return switch (emotion) {
      'happy' => 'wag_tail',
      'tired' => 'rest',
      'sad' || 'lonely' || 'anxious' => 'move_closer',
      _ => action == 'story' ? 'stay' : 'nod',
    };
  }

  String _companionMode(String emotion, String action, UserStateHints state) {
    if (_isLowMood(emotion, '', state)) return 'emotional_companion';
    return switch (action) {
      'story' => 'story_companion',
      'news' || 'search' => 'knowledge_companion',
      'reminder' || 'task' => 'supportive_action',
      _ => 'soft_chat',
    };
  }

  bool _isLowMood(String emotion, String text, UserStateHints state) {
    return emotion == 'lonely' ||
        emotion == 'sad' ||
        emotion == 'tired' ||
        emotion == 'anxious' ||
        state.mentionedLonely ||
        state.mentionedTired ||
        state.mentionedPoorSleep ||
        state.mentionedLowAppetite ||
        state.mentionedPainOrDiscomfort ||
        text.contains('家裡好安靜') ||
        text.contains('足安靜') ||
        text.contains('沒有人陪') ||
        text.contains('不太想吃飯') ||
        text.contains('睡不好') ||
        text.contains('袂好睏');
  }

  UserStateHints _stateFromContext(CompanionContext context) {
    final provided = context.userStateHints;
    final text = context.userText;
    final recent = context.conversationHistory
        .take(3)
        .map((turn) => turn.userText)
        .join(' ');
    final combined = '$recent $text';
    return UserStateHints(
      mentionedLonely: provided.mentionedLonely ||
          _containsAny(
              combined, ['孤單', '沒有人陪', '沒什麼人陪', '沒人陪', '家裡好安靜', '足安靜', '厝內']),
      mentionedTired: provided.mentionedTired ||
          _containsAny(combined, ['累', '疲倦', '沒精神', '想睡', '足累']),
      mentionedPoorSleep: provided.mentionedPoorSleep ||
          _containsAny(combined, ['睡不好', '睡不著', '失眠', '睡不太著', '袂好睏', '睏袂好']),
      mentionedLowAppetite: provided.mentionedLowAppetite ||
          _containsAny(combined, ['不太想吃飯', '沒胃口', '吃不下']),
      mentionedPainOrDiscomfort: provided.mentionedPainOrDiscomfort ||
          _containsAny(combined, ['不舒服', '痛', '疼', '頭暈']),
      lastConcernAt: provided.lastConcernAt,
    );
  }

  String _normalizeEmotion(String value) {
    return switch (value.trim()) {
      'happy' ||
      'sad' ||
      'lonely' ||
      'anxious' ||
      'tired' ||
      'nostalgic' =>
        value.trim(),
      _ => 'neutral',
    };
  }

  String _oneSentence(String text) {
    if (text.isEmpty) return '';
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final match = RegExp(r'^(.+?[。！？!?])').firstMatch(normalized);
    return (match?.group(1) ?? normalized)
        .replaceAll('？', '。')
        .replaceAll('?', '.');
  }

  String _variation(String key, String seed, List<String> options) {
    if (options.isEmpty) return '';
    final value = '$key|$seed'.runes.fold<int>(
          0,
          (previous, rune) => previous + rune,
        );
    return options[value.abs() % options.length];
  }

  bool _containsAny(String text, List<String> terms) {
    return terms.any(text.contains);
  }

  bool _usesTaigiVoice(ReplyLanguage replyLanguage) {
    return replyLanguage == ReplyLanguage.mixedZhTaigi ||
        replyLanguage == ReplyLanguage.taigi;
  }

  bool _referencesPreviousState(String text) {
    return _containsAny(text, ['剛剛', '前面', '也說', '有記著']);
  }

  String _limitToOneQuestion(String text) {
    var count = 0;
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      if (char == '？' || char == '?') {
        count += 1;
        if (count > 1) {
          buffer.write(char == '？' ? '。' : '.');
          continue;
        }
      }
      buffer.write(char);
    }
    return buffer.toString();
  }
}
