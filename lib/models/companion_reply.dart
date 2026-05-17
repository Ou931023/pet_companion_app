import 'conversation_turn.dart';
import 'language_route.dart';

class CompanionContext {
  const CompanionContext({
    required this.userText,
    required this.detectedEmotion,
    required this.fusedEmotion,
    required this.petName,
    this.memoryHints = const [],
    this.routeInfo = '',
    this.userStateHints = const UserStateHints(),
    this.suggestedAction = '',
    this.optionalSuggestion = '',
    this.conversationHistory = const [],
    this.replyLanguage = ReplyLanguage.zhTw,
  });

  final String userText;
  final String detectedEmotion;
  final String fusedEmotion;
  final List<String> memoryHints;
  final String routeInfo;
  final UserStateHints userStateHints;
  final String suggestedAction;
  final String optionalSuggestion;
  final String petName;
  final List<ConversationTurn> conversationHistory;
  final ReplyLanguage replyLanguage;
}

class UserStateHints {
  const UserStateHints({
    this.mentionedLonely = false,
    this.mentionedTired = false,
    this.mentionedPoorSleep = false,
    this.mentionedLowAppetite = false,
    this.mentionedPainOrDiscomfort = false,
    this.lastConcernAt,
  });

  final bool mentionedLonely;
  final bool mentionedTired;
  final bool mentionedPoorSleep;
  final bool mentionedLowAppetite;
  final bool mentionedPainOrDiscomfort;
  final DateTime? lastConcernAt;
}

class CompanionReplyPlan {
  const CompanionReplyPlan({
    required this.emotionalAck,
    required this.careQuestion,
    required this.continuationPrompt,
    required this.optionalSuggestion,
    required this.petExpression,
    required this.petAction,
    required this.companionMode,
  });

  final String emotionalAck;
  final String careQuestion;
  final String continuationPrompt;
  final String optionalSuggestion;
  final String petExpression;
  final String petAction;
  final String companionMode;
}

class CompanionReplyDebugInfo {
  const CompanionReplyDebugInfo({
    required this.detectedEmotion,
    required this.fusedEmotion,
    required this.companionMode,
    required this.petExpression,
    required this.petAction,
    required this.userStateHints,
    required this.referencedPreviousState,
    required this.optionalSuggestionDeferred,
  });

  final String detectedEmotion;
  final String fusedEmotion;
  final String companionMode;
  final String petExpression;
  final String petAction;
  final UserStateHints userStateHints;
  final bool referencedPreviousState;
  final bool optionalSuggestionDeferred;
}
