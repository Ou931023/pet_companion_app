import 'package:flutter/material.dart';

import '../models/companion_reply.dart';

class CompanionDebugPanel extends StatelessWidget {
  const CompanionDebugPanel({
    super.key,
    required this.info,
  });

  final CompanionReplyDebugInfo? info;

  @override
  Widget build(BuildContext context) {
    final debug = info;
    if (debug == null) {
      return const Text(
        '尚無 Companion Reply Strategy 資料，完成一輪對話後會顯示。',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DebugRow(label: 'detectedEmotion', value: debug.detectedEmotion),
        _DebugRow(label: 'fusedEmotion', value: debug.fusedEmotion),
        _DebugRow(label: 'companionMode', value: debug.companionMode),
        _DebugRow(label: 'petExpression', value: debug.petExpression),
        _DebugRow(label: 'petAction', value: debug.petAction),
        const SizedBox(height: 10),
        const Text(
          'userStateHints',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _HintChip(
              label: 'mentionedLonely',
              active: debug.userStateHints.mentionedLonely,
            ),
            _HintChip(
              label: 'mentionedTired',
              active: debug.userStateHints.mentionedTired,
            ),
            _HintChip(
              label: 'mentionedPoorSleep',
              active: debug.userStateHints.mentionedPoorSleep,
            ),
            _HintChip(
              label: 'mentionedLowAppetite',
              active: debug.userStateHints.mentionedLowAppetite,
            ),
            _HintChip(
              label: 'mentionedPainOrDiscomfort',
              active: debug.userStateHints.mentionedPainOrDiscomfort,
            ),
          ],
        ),
        const SizedBox(height: 10),
        _DebugRow(
          label: '引用前一輪狀態',
          value: debug.referencedPreviousState ? '是' : '否',
        ),
        _DebugRow(
          label: 'optionalSuggestion 延後/壓低',
          value: debug.optionalSuggestionDeferred ? '是' : '否',
        ),
      ],
    );
  }
}

class _DebugRow extends StatelessWidget {
  const _DebugRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _HintChip extends StatelessWidget {
  const _HintChip({
    required this.label,
    required this.active,
  });

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(
        active ? Icons.check_circle : Icons.radio_button_unchecked,
        size: 18,
        color: active ? Colors.green.shade700 : Colors.black45,
      ),
      label: Text('$label: ${active ? 'true' : 'false'}'),
    );
  }
}
