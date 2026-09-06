import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/models/companion_reply.dart';
import 'package:pet_companion_app/models/conversation_turn.dart';
import 'package:pet_companion_app/models/language_route.dart';
import 'package:pet_companion_app/services/companion_reply_strategy_service.dart';

void main() {
  const strategy = CompanionReplyStrategyService();

  group('CompanionReplyStrategyService', () {
    for (final item in [
      (
        text: '今天家裡好安靜',
        emotion: 'lonely',
        action: '',
        mode: 'emotional_companion',
        suggestion: '我可以幫你查附近活動。',
      ),
      (
        text: '我有點累',
        emotion: 'tired',
        action: '',
        mode: 'emotional_companion',
        suggestion: '你可以先去完成每日任務。',
      ),
      (
        text: '沒有人陪我',
        emotion: 'lonely',
        action: '',
        mode: 'emotional_companion',
        suggestion: '我可以幫你找新聞。',
      ),
      (
        text: '我今天不太想吃飯',
        emotion: 'sad',
        action: '',
        mode: 'emotional_companion',
        suggestion: '建議你立刻吃一大碗飯。',
      ),
      (
        text: '我睡不好',
        emotion: 'anxious',
        action: '',
        mode: 'emotional_companion',
        suggestion: '我可以查睡眠衛教。',
      ),
      (
        text: '講個故事給我聽',
        emotion: 'neutral',
        action: 'story',
        mode: 'story_companion',
        suggestion: '從前有一個溫柔的小村莊。',
      ),
      (
        text: '今天有什麼新聞',
        emotion: 'neutral',
        action: 'news',
        mode: 'knowledge_companion',
        suggestion: '今天的新聞重點是天氣轉涼。',
      ),
    ]) {
      test('${item.text} uses companion-first reply plan', () {
        final plan = strategy.buildPlan(
          CompanionContext(
            userText: item.text,
            detectedEmotion: item.emotion,
            fusedEmotion: item.emotion,
            petName: '陪伴寶',
            suggestedAction: item.action,
            optionalSuggestion: item.suggestion,
          ),
        );
        final reply = strategy.compose(plan);

        expect(plan.emotionalAck, isNotEmpty);
        expect(plan.companionMode, item.mode);
        expect(plan.petExpression, isNot(''));
        expect(_questionCount(reply), lessThanOrEqualTo(1));
        expect(_hasEmotionalCare(reply), isTrue);
        if (item.mode == 'emotional_companion') {
          expect(plan.optionalSuggestion, isEmpty);
        }
      });
    }

    test('second turn references poor sleep when user later feels tired', () {
      final plan = strategy.buildPlan(
        CompanionContext(
          userText: '我有點累',
          detectedEmotion: 'tired',
          fusedEmotion: 'tired',
          petName: '陪伴寶',
          userStateHints: UserStateHints(
            mentionedPoorSleep: true,
            lastConcernAt: DateTime(2026, 5, 16, 10),
          ),
          optionalSuggestion: '我可以幫你查睡眠衛教。',
          suggestedAction: 'search',
        ),
      );
      final reply = strategy.compose(plan);

      expect(reply, contains('睡得不太好'));
      expect(reply, contains('累'));
      expect(plan.optionalSuggestion, isEmpty);
      expect(plan.companionMode, 'emotional_companion');
      expect(_questionCount(reply), lessThanOrEqualTo(1));
    });

    test('second lonely turn references previous quiet-home state', () {
      final plan = strategy.buildPlan(
        CompanionContext(
          userText: '沒什麼人陪我',
          detectedEmotion: 'lonely',
          fusedEmotion: 'lonely',
          petName: '陪伴寶',
          userStateHints: UserStateHints(
            mentionedLonely: true,
            lastConcernAt: DateTime(2026, 5, 16, 10),
          ),
          optionalSuggestion: '我可以幫你找新聞。',
          suggestedAction: 'news',
        ),
      );
      final reply = strategy.compose(plan);

      expect(reply, contains('剛剛'));
      expect(reply, contains('沒什麼人陪'));
      expect(plan.optionalSuggestion, isEmpty);
      expect(plan.companionMode, 'emotional_companion');
      expect(_questionCount(reply), lessThanOrEqualTo(1));
    });

    test('taigi cue reply uses mixed zh taigi voice', () {
      final reply = strategy.buildReply(
        const CompanionContext(
          userText: '今仔日厝內足安靜',
          detectedEmotion: 'lonely',
          fusedEmotion: 'lonely',
          petName: '陪伴寶',
          replyLanguage: ReplyLanguage.mixedZhTaigi,
        ),
      );

      expect(_hasTaigiVoice(reply), isTrue);
      expect(_questionCount(reply), lessThanOrEqualTo(1));
    });

    test('poor sleep taigi reply keeps companion-first tone', () {
      final reply = strategy.buildReply(
        const CompanionContext(
          userText: '我袂好睏',
          detectedEmotion: 'tired',
          fusedEmotion: 'tired',
          petName: '陪伴寶',
          replyLanguage: ReplyLanguage.mixedZhTaigi,
        ),
      );

      expect(_hasTaigiVoice(reply), isTrue);
      expect(reply, contains('袂好睏'));
      expect(reply, contains('陪'));
      expect(_questionCount(reply), lessThanOrEqualTo(1));
    });

    test('zh-TW reply keeps Mandarin voice', () {
      final reply = strategy.buildReply(
        const CompanionContext(
          userText: '今天家裡好安靜',
          detectedEmotion: 'lonely',
          fusedEmotion: 'lonely',
          petName: '陪伴寶',
          replyLanguage: ReplyLanguage.zhTw,
        ),
      );

      expect(_hasTaigiVoice(reply), isFalse);
      expect(reply, contains('陪'));
      expect(_questionCount(reply), lessThanOrEqualTo(1));
    });

    test('中文／台語／混合語言一般回覆維持 1 到 3 句且最多一問', () {
      final contexts = [
        const CompanionContext(
          userText: '今天心情很好，去公園走了一圈',
          detectedEmotion: 'happy',
          fusedEmotion: 'happy',
          petName: '陪伴寶',
          optionalSuggestion: '晚一點也可以聽音樂。再喝一杯水。',
        ),
        const CompanionContext(
          userText: '我今天有點難過',
          detectedEmotion: 'sad',
          fusedEmotion: 'sad',
          petName: '陪伴寶',
        ),
        const CompanionContext(
          userText: '今仔日厝內足安靜',
          detectedEmotion: 'lonely',
          fusedEmotion: 'lonely',
          petName: '陪伴寶',
          replyLanguage: ReplyLanguage.taigi,
        ),
        const CompanionContext(
          userText: '我昨暝袂好睏，今仔日足累',
          detectedEmotion: 'tired',
          fusedEmotion: 'tired',
          petName: '陪伴寶',
          replyLanguage: ReplyLanguage.mixedZhTaigi,
        ),
      ];

      for (final context in contexts) {
        final reply = strategy.buildReply(context);
        expect(
          _sentenceCount(reply),
          inInclusiveRange(1, 3),
          reason: '一般語音不應過長：$reply',
        );
        expect(
          _questionCount(reply),
          lessThanOrEqualTo(1),
          reason: '一次最多問一題：$reply',
        );
      }
    });

    test('有情緒時第一句先接住情緒', () {
      for (final item in [
        (
          context: const CompanionContext(
            userText: '我今天很難過',
            detectedEmotion: 'sad',
            fusedEmotion: 'sad',
            petName: '陪伴寶',
          ),
          emotionCue: RegExp(r'低落|不太輕鬆|難受'),
        ),
        (
          context: const CompanionContext(
            userText: '我袂好睏',
            detectedEmotion: 'tired',
            fusedEmotion: 'tired',
            petName: '陪伴寶',
            replyLanguage: ReplyLanguage.mixedZhTaigi,
          ),
          emotionCue: RegExp(r'袂好睏|睏袂好|無睏好'),
        ),
      ]) {
        final reply = strategy.buildReply(item.context);
        expect(
          item.emotionCue.hasMatch(_firstSentence(reply)),
          isTrue,
          reason: '第一句應先接住情緒：$reply',
        );
      }
    });

    test('連續相同內容不重複同一個開場', () {
      const context = CompanionContext(
        userText: '我今天很難過',
        detectedEmotion: 'sad',
        fusedEmotion: 'sad',
        petName: '陪伴寶',
      );
      final firstReply = strategy.buildReply(context);
      final secondReply = strategy.buildReply(
        CompanionContext(
          userText: context.userText,
          detectedEmotion: context.detectedEmotion,
          fusedEmotion: context.fusedEmotion,
          petName: context.petName,
          conversationHistory: [
            ConversationTurn(
              timestamp: DateTime(2026, 9, 2, 10),
              userText: context.userText,
              petReply: firstReply,
              toolName: 'chat',
            ),
          ],
        ),
      );

      expect(_firstSentence(secondReply), isNot(_firstSentence(firstReply)));
    });

    test('compose 對過長內容硬限制三句並保留最多一個問題', () {
      const plan = CompanionReplyPlan(
        emotionalAck: '今天真的很難受，我有聽見。',
        careQuestion: '你想先休息嗎？你有喝水嗎？',
        continuationPrompt: '我們慢慢來。',
        optionalSuggestion: '先坐一下。晚點再走動。',
        petExpression: 'concerned',
        petAction: 'move_closer',
        companionMode: 'emotional_companion',
      );

      final reply = strategy.compose(plan);

      expect(reply, startsWith(plan.emotionalAck));
      expect(_sentenceCount(reply), 3);
      expect(_questionCount(reply), 1);
      expect(reply, isNot(contains('先坐一下')));
    });
  });
}

bool _hasEmotionalCare(String reply) {
  return [
    '聽起來',
    '我聽得出來',
    '我聽見',
    '陪',
    '靠近',
    '旁邊',
    '慢慢',
    '好呀',
    '嗯嗯',
  ].any(reply.contains);
}

int _questionCount(String value) {
  return RegExp(r'[？?]').allMatches(value).length;
}

int _sentenceCount(String value) {
  return RegExp(r'[^。！？!?\.]+[。！？!?\.]?')
      .allMatches(value.trim())
      .where((match) => (match.group(0) ?? '').trim().isNotEmpty)
      .length;
}

String _firstSentence(String value) {
  return RegExp(r'^[^。！？!?\.]+[。！？!?\.]?')
          .firstMatch(value.trim())
          ?.group(0)
          ?.trim() ??
      '';
}

bool _hasTaigiVoice(String reply) {
  return [
    '今仔日',
    '佇',
    '袂',
    '足',
    '欲',
    '毋',
    '咱',
    '齁',
    '厝',
  ].any(reply.contains);
}
