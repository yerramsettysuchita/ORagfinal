import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/chat_message.dart';
import '../theme/app_theme.dart';

/// A styled chat bubble for user or AI messages.
/// AI messages render markdown (bold, code, lists, headings).
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
      child: isUser ? _userText() : _aiMarkdown(),
    );
  }

  /// Plain text for user messages.
  Widget _userText() {
    return SelectableText(
      message.text,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 14.5,
        height: 1.5,
      ),
    );
  }

  /// Markdown-rendered text for AI messages.
  Widget _aiMarkdown() {
    final text =
        message.text.isEmpty && message.isStreaming ? ' ' : message.text;

    return MarkdownBody(
      data: text,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        // Body text
        p: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14.5,
          height: 1.6,
        ),
        // Bold
        strong: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
        // Italic
        em: const TextStyle(
          color: AppColors.textPrimary,
          fontStyle: FontStyle.italic,
        ),
        // Inline code + code block text (same property)
        code: TextStyle(
          color: AppColors.primary,
          backgroundColor: AppColors.surfaceLight.withValues(alpha: 0.6),
          fontSize: 13,
          fontFamily: 'monospace',
        ),
        // Code block container
        codeblockDecoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.divider, width: 1),
        ),
        codeblockPadding: const EdgeInsets.all(12),
        // Headings
        h1: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          height: 1.4,
        ),
        h2: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
        h3: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
        // List bullets
        listBullet: const TextStyle(
          color: AppColors.primary,
          fontSize: 14.5,
        ),
        // Blockquote
        blockquote: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 14,
          fontStyle: FontStyle.italic,
        ),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: AppColors.secondary.withValues(alpha: 0.4),
              width: 3,
            ),
          ),
        ),
        blockquotePadding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
        // Horizontal rule
        horizontalRuleDecoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: AppColors.divider,
              width: 1,
            ),
          ),
        ),
        // Table
        tableHead: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        tableBody: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
        ),
        tableBorder: TableBorder.all(
          color: AppColors.divider,
          width: 1,
        ),
        // Links
        a: const TextStyle(
          color: AppColors.primary,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }
}
