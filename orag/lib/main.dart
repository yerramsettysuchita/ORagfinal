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

  final TextEditingController _controller = TextEditingController();
  List<String> messages = [];
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      initPython();
    });
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

  Future<void> sendMessage() async {
    if (isLoading) return;

    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();

    setState(() {
      isLoading = true;
      messages.add('You: $text');
    });

    try {
      final response = await platform.invokeMethod('chat', {
        'query': text,
      });

      setState(() {
        messages.add('AI: $response');
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        messages.add('Error: $e');
        isLoading = false;
      });
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
              itemCount: messages.length,
              itemBuilder: (context, index) {
                return ListTile(title: Text(messages[index]));
              },
            ),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(controller: _controller),
              ),
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: isLoading ? null : sendMessage,
              )
            ],
          )
        ],
      ),
    );
  }
}
