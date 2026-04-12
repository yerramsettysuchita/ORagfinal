import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../theme/app_theme.dart';

/// A styled chat bubble for user or AI messages.
class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;

    return Padding(
      padding: EdgeInsets.only(
        left: isUser ? 48 : 12,
        right: isUser ? 12 : 48,
        top: 4,
        bottom: 4,
      ),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) _avatar(isUser),
          if (!isUser) const SizedBox(width: 8),
          Flexible(child: _bubble(isUser)),
          if (isUser) const SizedBox(width: 8),
          if (isUser) _avatar(isUser),
        ],
      ),
    );
  }

  Widget _avatar(bool isUser) {
    return Container(
      width: 30,
      height: 30,
      margin: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(
        color: isUser
            ? AppColors.primary.withValues(alpha: 0.15)
            : AppColors.secondary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        isUser ? Icons.person_rounded : Icons.auto_awesome_rounded,
        size: 16,
        color: isUser ? AppColors.primary : AppColors.secondary,
      ),
    );
  }

  Widget _bubble(bool isUser) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isUser ? AppColors.userBubble : AppColors.aiBubble,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isUser ? 18 : 4),
          bottomRight: Radius.circular(isUser ? 4 : 18),
        ),
        border: Border.all(
          color: isUser
              ? AppColors.primary.withValues(alpha: 0.08)
              : AppColors.divider,
          width: 1,
        ),
      ),
      child: SelectableText(
        message.text.isEmpty && message.isStreaming ? ' ' : message.text,
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14.5,
          height: 1.5,
          fontWeight: isUser ? FontWeight.w400 : FontWeight.w400,
        ),
      ),
    );
  }
}
