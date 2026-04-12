import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../models/chat_message.dart';
import '../services/platform_service.dart';
import '../theme/app_theme.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/init_overlay.dart';
import '../widgets/typing_indicator.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final PlatformService _platform = PlatformService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<ChatMessage> _messages = [];
  bool _isGenerating = false;
  StreamSubscription<String>? _chatSub;

  // Init state
  InitStatus _initStatus = const InitStatus(state: InitState.idle);
  bool _initDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startInit());
  }

  @override
  void dispose() {
    _chatSub?.cancel();
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  // ---- Init flow ----

  Future<void> _startInit() async {
    setState(() {
      _initStatus = const InitStatus(
        state: InitState.idle,
        message: 'Preparing the AI engine…',
      );
      _initDone = false;
    });

    try {
      final dir = await getExternalStorageDirectory();
      final modelPath = '${dir!.path}/models';

      _platform.initPython(modelPath).listen(
        (status) {
          if (!mounted) return;
          setState(() {
            _initStatus = status;
            if (status.isReady) _initDone = true;
          });
        },
        onError: (e) {
          if (!mounted) return;
          setState(() {
            _initStatus = InitStatus(
              state: InitState.error,
              progress: 1.0,
              message: 'Init failed: $e',
            );
          });
        },
        onDone: () {
          // If the stream closed without a ready/error event,
          // poll for status once as fallback.
          if (!_initDone && mounted) {
            _pollStatus();
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _initStatus = InitStatus(
            state: InitState.error,
            progress: 1.0,
            message: 'Failed to start: $e',
          );
        });
      }
    }
  }

  Future<void> _pollStatus() async {
    // Fallback: if the init EventChannel didn't fire, try polling.
    // Also handles the case where init was already done before we listened.
    for (var i = 0; i < 60; i++) {
      if (_initDone || !mounted) return;
      final s = await _platform.getStatus();
      if (!mounted) return;
      setState(() => _initStatus = s);
      if (s.isReady) {
        setState(() => _initDone = true);
        return;
      }
      if (s.isError) return;
      await Future.delayed(const Duration(seconds: 2));
    }
  }

  // ---- Chat ----

  void _sendMessage() {
    if (_isGenerating || !_initDone) return;
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();

    final userMsg = ChatMessage(role: MessageRole.user, text: text);
    final aiMsg = ChatMessage(
      role: MessageRole.assistant,
      text: '',
      isStreaming: true,
    );

    setState(() {
      _messages.add(userMsg);
      _messages.add(aiMsg);
      _isGenerating = true;
    });
    _scrollToBottom();

    _chatSub?.cancel();
    _chatSub = _platform.chatStream(text).listen(
      (token) {
        if (!mounted) return;
        setState(() {
          aiMsg.text += token;
        });
        _scrollToBottom();
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          aiMsg.text += '\n⚠️ Error: $error';
          aiMsg.isStreaming = false;
          _isGenerating = false;
        });
      },
      onDone: () {
        if (!mounted) return;
        setState(() {
          if (aiMsg.isEmpty) {
            aiMsg.text = '(empty response)';
          }
          aiMsg.isStreaming = false;
          _isGenerating = false;
        });
      },
    );
  }

  Future<void> _stopGeneration() async {
    await _platform.stop();
    // The stream onDone will handle the state cleanup
  }

  Future<void> _clearMemory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Clear conversation?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'This will clear all messages and conversation memory.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _platform.clearMemory();
        setState(() => _messages.clear());
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to clear: $e')),
          );
        }
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Main chat UI
          Column(
            children: [
              _buildAppBar(),
              Expanded(child: _buildMessageList()),
              ChatInputBar(
                controller: _controller,
                enabled: _initDone,
                isGenerating: _isGenerating,
                onSend: _sendMessage,
                onStop: _stopGeneration,
              ),
            ],
          ),

          // Init overlay (shown on top until ready)
          if (!_initDone)
            InitOverlay(
              status: _initStatus,
              onRetry: _startInit,
            ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 16,
        right: 8,
        bottom: 12,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.divider, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Logo accent
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.secondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          // Title
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'O-RAG',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Offline AI Assistant',
                  style: TextStyle(
                    color: AppColors.textDim,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          // Clear button
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 22),
            tooltip: 'Clear conversation',
            onPressed: (_isGenerating || _messages.isEmpty) ? null : _clearMemory,
            color: AppColors.textSecondary,
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    if (_messages.isEmpty && _initDone) {
      return _buildEmptyState();
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: _messages.length + (_isGenerating && _messages.last.isEmpty ? 1 : 0),
      itemBuilder: (context, index) {
        // Show typing indicator as the last item when AI hasn't produced tokens yet
        if (index == _messages.length) {
          return const TypingIndicator();
        }

        final msg = _messages[index];

        // If this is the AI message and it's streaming but empty, show typing indicator
        if (msg.isAssistant && msg.isStreaming && msg.isEmpty) {
          return const TypingIndicator();
        }

        return ChatBubble(message: msg);
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.chat_bubble_outline_rounded,
              size: 32,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Ask me anything',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your offline AI assistant is ready',
            style: TextStyle(
              color: AppColors.textDim,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
