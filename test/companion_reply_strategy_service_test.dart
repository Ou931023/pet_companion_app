import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/models/companion_reply.dart';
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
