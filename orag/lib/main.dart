import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const platform = MethodChannel('orag');
  static const streamChannel = EventChannel('orag_stream');

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<String> messages = [];
  bool isLoading = false;
  StreamSubscription? _streamSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      initPython();
    });
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> initPython() async {
    try {
      final path = await getModelPath();
      await platform.invokeMethod('initPython', {
        'model_path': path,
      });
    } catch (_) {
      // Ignore warmup errors; chat call will surface issues if initialization fails.
    }
  }

  Future<String> getModelPath() async {
    final Directory? dir = await getExternalStorageDirectory();
    return '${dir!.path}/models';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _stopGeneration() async {
    try {
      await platform.invokeMethod('stop');
    } catch (e) {
      debugPrint("Failed to stop: $e");
    }
  }

  Future<void> sendMessage() async {
    if (isLoading) return;

    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();

    setState(() {
      isLoading = true;
      messages.add('You: $text');
      messages.add('AI: ');  // Placeholder for streamed response
    });
    _scrollToBottom();

    // Start listening to the token stream BEFORE invoking chatStream
    _streamSub?.cancel();
    _streamSub = streamChannel.receiveBroadcastStream().listen(
      (event) {
        final token = event.toString();
        if (token == '__STREAM_END__') {
          // Generation finished — clean up empty response if needed
          setState(() {
            if (messages.isNotEmpty && messages.last == 'AI: ') {
              messages[messages.length - 1] = 'AI: (empty response)';
            }
            isLoading = false;
          });
          _streamSub?.cancel();
          return;
        }
        // Append token to the last message (the AI response)
        setState(() {
          messages[messages.length - 1] += token;
        });
        _scrollToBottom();
      },
      onError: (error) {
        setState(() {
          messages[messages.length - 1] += '\nError: $error';
          isLoading = false;
        });
        _streamSub?.cancel();
      },
    );

    // Trigger streaming generation on the platform side
    try {
      await platform.invokeMethod('chatStream', {
        'query': text,
      });
    } catch (e) {
      setState(() {
        if (messages.isNotEmpty) {
          messages[messages.length - 1] = 'Error: $e';
        }
        isLoading = false;
      });
      _streamSub?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('O-RAG')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: messages.length,
              itemBuilder: (context, index) {
                return ListTile(title: Text(messages[index]));
              },
            ),
          ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: !isLoading,
                    decoration: InputDecoration(
                        hintText: isLoading ? "Thinking..." : "Type a message",
                    ),
                    onSubmitted: (_) => sendMessage(),
                  ),
                ),
                if (isLoading)
                  IconButton(
                    icon: const Icon(Icons.stop_circle, color: Colors.red),
                    onPressed: _stopGeneration,
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: sendMessage,
                  )
              ],
            )
        ],
      ),
    );
  }
}
