import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/models/agent_tool_intent.dart';

void main() {
  test('AgentToolIntent parses json and exposes safety helpers', () {
    final intent = AgentToolIntent.fromJson({
      'id': 'agent_tool_1',
      'toolName': 'open_phone_dialer',
      'displayName': '開啟撥號畫面',
      'arguments': {'contactName': '女兒'},
      'requiresConfirmation': true,
      'riskLevel': 'high',
      'status': 'pending',
      'userFacingMessage': '要幫你開啟撥號畫面嗎？',
      'createdAt': '2026-05-19T12:00:00.000Z',
    });

    expect(intent.isHighRisk, isTrue);
    expect(intent.isExecutable, isTrue);
    expect(intent.toJson()['riskLevel'], 'high');
    expect(
      intent.copyWith(status: AgentToolStatus.executed).isExecutable,
      isFalse,
    );
  });
}
