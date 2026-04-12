import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Chat text input bar with three visual states:
///  - Disabled (during init): grayed out, "AI is loading…"
///  - Ready: active input with send button
///  - Generating: disabled, shows animated stop button
class ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final bool isGenerating;
  final VoidCallback onSend;
  final VoidCallback onStop;

  const ChatInputBar({
    super.key,
    required this.controller,
    required this.enabled,
    required this.isGenerating,
    required this.onSend,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.divider, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.inputFill,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.inputBorder, width: 1),
                ),
                child: TextField(
                  controller: controller,
                  enabled: enabled && !isGenerating,
                  maxLines: 4,
                  minLines: 1,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                  ),
                  decoration: InputDecoration(
                    hintText: _hintText,
                    hintStyle: const TextStyle(
                      color: AppColors.textDim,
                      fontSize: 15,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                  ),
                  textInputAction: TextInputAction.send,
                  onSubmitted: enabled && !isGenerating ? (_) => onSend() : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _actionButton(),
          ],
        ),
      ),
    );
  }

  String get _hintText {
    if (!enabled) return 'AI is loading…';
    if (isGenerating) return 'Generating…';
    return 'Ask me anything…';
  }

  Widget _actionButton() {
    if (isGenerating) {
      return _StopButton(onTap: onStop);
    }
    return _SendButton(
      onTap: enabled ? onSend : null,
    );
  }
}

class _SendButton extends StatelessWidget {
  final VoidCallback? onTap;
  const _SendButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final active = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color:
              active ? AppColors.primary : AppColors.primary.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Icon(
          Icons.arrow_upward_rounded,
          color:
              active ? AppColors.background : AppColors.textDim,
          size: 22,
        ),
      ),
    );
  }
}

class _StopButton extends StatefulWidget {
  final VoidCallback onTap;
  const _StopButton({required this.onTap});

  @override
  State<_StopButton> createState() => _StopButtonState();
}

class _StopButtonState extends State<_StopButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          return Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.error
                  .withValues(alpha: 0.8 + 0.2 * _pulse.value),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: AppColors.error.withValues(alpha: 0.3 * _pulse.value),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(
              Icons.stop_rounded,
              color: Colors.white,
              size: 22,
            ),
          );
        },
      ),
    );
  }
}
