import 'dart:async';

import 'package:flutter/material.dart';

enum ElderFeedbackTone { info, success, warning }

/// 長者友善的全 App 訊息提示。
///
/// 一般狀態顯示在畫面上方且同時只有一則；新的訊息會立即取代舊訊息，避免排隊
/// 殘留。需要使用者留意的錯誤則使用有「知道了」按鈕的對話框。
class ElderFeedback {
  ElderFeedback._();

  static OverlayEntry? _activeEntry;

  static void show(
    BuildContext context,
    String message, {
    ElderFeedbackTone tone = ElderFeedbackTone.info,
    Duration duration = const Duration(seconds: 3),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final normalized = message.trim();
    if (normalized.isEmpty) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final sourceRoute = ModalRoute.of(context);

    hide();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayContext) => _ElderFeedbackBubble(
        message: normalized,
        tone: tone,
        duration: duration,
        actionLabel: actionLabel,
        onDismiss: () => _remove(entry),
        onAction: onAction == null
            ? null
            : () {
                _remove(entry);
                onAction();
              },
      ),
    );
    _activeEntry = entry;
    overlay.insert(entry);
    if (sourceRoute != null) {
      void removeAfterRouteChange(Duration _) {
        if (!entry.mounted) return;
        if (!sourceRoute.isCurrent) {
          _remove(entry);
          return;
        }
        WidgetsBinding.instance.addPostFrameCallback(removeAfterRouteChange);
      }

      WidgetsBinding.instance.addPostFrameCallback(removeAfterRouteChange);
    }
  }

  static void showImportant(
    BuildContext context,
    String message, {
    String title = '請留意',
  }) {
    hide();
    unawaited(
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          content: Semantics(
            liveRegion: true,
            child: Text(
              message,
              style: const TextStyle(fontSize: 18, height: 1.45),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: FilledButton.styleFrom(
                minimumSize: const Size(112, 52),
              ),
              child: const Text(
                '知道了',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static void hide() {
    final entry = _activeEntry;
    _activeEntry = null;
    if (entry != null) _remove(entry);
  }

  static void _remove(OverlayEntry entry) {
    if (identical(_activeEntry, entry)) {
      _activeEntry = null;
    }
    if (entry.mounted) entry.remove();
  }
}

class _ElderFeedbackBubble extends StatefulWidget {
  const _ElderFeedbackBubble({
    required this.message,
    required this.tone,
    required this.duration,
    required this.onDismiss,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final ElderFeedbackTone tone;
  final Duration duration;
  final VoidCallback onDismiss;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  State<_ElderFeedbackBubble> createState() => _ElderFeedbackBubbleState();
}

class _ElderFeedbackBubbleState extends State<_ElderFeedbackBubble> {
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _dismissTimer = Timer(widget.duration, widget.onDismiss);
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = switch (widget.tone) {
      ElderFeedbackTone.success => (
          background: const Color(0xFFEAF7EF),
          foreground: const Color(0xFF176B3A),
          icon: Icons.check_circle_outline,
        ),
      ElderFeedbackTone.warning => (
          background: const Color(0xFFFFF4E5),
          foreground: const Color(0xFF8A4B08),
          icon: Icons.info_outline,
        ),
      ElderFeedbackTone.info => (
          background: const Color(0xFFF2F5FF),
          foreground: const Color(0xFF273B78),
          icon: Icons.info_outline,
        ),
    };
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 12,
      left: 16,
      right: 16,
      child: SafeArea(
        bottom: false,
        child: Semantics(
          container: true,
          liveRegion: true,
          label: widget.message,
          child: Material(
            color: colors.background,
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: widget.onDismiss,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 64),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Icon(colors.icon, color: colors.foreground, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.message,
                          style: TextStyle(
                            color: colors.foreground,
                            fontSize: 18,
                            height: 1.35,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (widget.actionLabel != null &&
                          widget.onAction != null) ...[
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: widget.onAction,
                          style: TextButton.styleFrom(
                            minimumSize: const Size(72, 48),
                            foregroundColor: colors.foreground,
                          ),
                          child: Text(
                            widget.actionLabel!,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
