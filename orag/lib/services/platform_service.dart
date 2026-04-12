import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';

/// Represents the current state of the model initialization pipeline.
enum InitState { idle, downloading, loading, ready, error }

class InitStatus {
  final InitState state;
  final double progress; // 0.0 – 1.0
  final String message;

  const InitStatus({
    this.state = InitState.idle,
    this.progress = 0.0,
    this.message = '',
  });

  bool get isReady => state == InitState.ready;
  bool get isBusy =>
      state == InitState.downloading || state == InitState.loading;
  bool get isError => state == InitState.error;
}

/// Typed wrapper around the native platform channels (Kotlin ↔ Flutter).
class PlatformService {
  static const _method = MethodChannel('orag');
  static const _streamChannel = EventChannel('orag_stream');
  static const _initChannel = EventChannel('orag_init_progress');

  // ---- Init / bootstrap ----

  /// Start Python + download models + load LLM.
  /// Returns a stream of [InitStatus] updates.
  Stream<InitStatus> initPython(String modelPath) {
    // The init progress comes through a dedicated EventChannel.
    // We trigger the init via MethodChannel, and listen for progress
    // on the EventChannel.
    final controller = StreamController<InitStatus>();

    // Listen to init progress events first
    StreamSubscription? sub;
    sub = _initChannel.receiveBroadcastStream().listen(
      (event) {
        try {
          final map = event is Map
              ? event.cast<String, dynamic>()
              : jsonDecode(event.toString()) as Map<String, dynamic>;
          final state = _parseState(map['state'] as String? ?? 'idle');
          final progress = (map['progress'] as num?)?.toDouble() ?? 0.0;
          final message = map['message'] as String? ?? '';
          controller.add(InitStatus(
            state: state,
            progress: progress,
            message: message,
          ));
          if (state == InitState.ready || state == InitState.error) {
            sub?.cancel();
            controller.close();
          }
        } catch (e) {
          // Ignore malformed events
        }
      },
      onError: (error) {
        controller.add(InitStatus(
          state: InitState.error,
          progress: 1.0,
          message: 'Init stream error: $error',
        ));
        controller.close();
      },
    );

    // Trigger init (fire-and-forget — progress comes via EventChannel)
    _method.invokeMethod('initPython', {'model_path': modelPath}).catchError(
      (e) {
        controller.add(InitStatus(
          state: InitState.error,
          progress: 1.0,
          message: 'Init failed: $e',
        ));
        if (!controller.isClosed) controller.close();
      },
    );

    return controller.stream;
  }

  /// One-shot status check (polling fallback).
  Future<InitStatus> getStatus() async {
    try {
      final result = await _method.invokeMethod('getStatus');
      if (result is Map) {
        final map = result.cast<String, dynamic>();
        return InitStatus(
          state: _parseState(map['state'] as String? ?? 'idle'),
          progress: (map['progress'] as num?)?.toDouble() ?? 0.0,
          message: map['message'] as String? ?? '',
        );
      }
    } catch (_) {}
    return const InitStatus();
  }

  // ---- Chat ----

  /// Start streaming chat. Returns a broadcast stream of token strings.
  /// The stream emits individual tokens as they arrive.
  /// When generation is finished, '__STREAM_END__' is emitted then the
  /// stream effectively finishes (caller should cancel subscription).
  Stream<String> chatStream(String query) {
    final controller = StreamController<String>();

    StreamSubscription? sub;
    sub = _streamChannel.receiveBroadcastStream().listen(
      (event) {
        final token = event.toString();
        if (token == '__STREAM_END__') {
          sub?.cancel();
          controller.close();
        } else {
          controller.add(token);
        }
      },
      onError: (error) {
        controller.addError(error);
        controller.close();
      },
    );

    _method.invokeMethod('chatStream', {'query': query}).catchError((e) {
      controller.addError(e);
      if (!controller.isClosed) controller.close();
    });

    return controller.stream;
  }

  /// Stop current generation.
  Future<void> stop() async {
    try {
      await _method.invokeMethod('stop');
    } catch (_) {}
  }

  /// Clear conversation memory.
  Future<void> clearMemory() async {
    await _method.invokeMethod('clearMemory');
  }

  // ---- Documents ----

  /// Upload a document (PDF/TXT) for RAG ingestion.
  /// Returns {success: bool, message: String}
  Future<Map<String, dynamic>> uploadDocument(String filePath) async {
    try {
      final result = await _method.invokeMethod(
        'uploadDocument',
        {'file_path': filePath},
      );
      return jsonDecode(result as String) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': 'Upload failed: $e'};
    }
  }

  /// List all ingested documents.
  Future<List<Map<String, dynamic>>> listDocuments() async {
    try {
      final result = await _method.invokeMethod('listDocuments');
      final list = jsonDecode(result as String) as List;
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// Delete a document by ID.
  Future<bool> deleteDocument(int docId) async {
    try {
      final result = await _method.invokeMethod(
        'deleteDocument',
        {'doc_id': docId},
      );
      final json = jsonDecode(result as String) as Map<String, dynamic>;
      return json['success'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Clear all documents.
  Future<bool> clearDocuments() async {
    try {
      final result = await _method.invokeMethod('clearDocuments');
      final json = jsonDecode(result as String) as Map<String, dynamic>;
      return json['success'] == true;
    } catch (_) {
      return false;
    }
  }

  // ---- RAG query ----

  /// Start a RAG streaming query. Streams tokens, then returns sources via
  /// the MethodChannel result (JSON with answer + sources).
  /// Returns a record of (tokenStream, sourcesFuture).
  ({Stream<String> tokens, Future<Map<String, dynamic>> result}) ragStream(String query) {
    final tokenController = StreamController<String>();
    final resultCompleter = Completer<Map<String, dynamic>>();

    StreamSubscription? sub;
    sub = _streamChannel.receiveBroadcastStream().listen(
      (event) {
        final token = event.toString();
        if (token == '__STREAM_END__') {
          sub?.cancel();
          tokenController.close();
        } else {
          tokenController.add(token);
        }
      },
      onError: (error) {
        tokenController.addError(error);
        tokenController.close();
      },
    );

    // Invoke ragStream — the result contains sources JSON
    _method.invokeMethod('ragStream', {'query': query}).then((result) {
      try {
        final json = jsonDecode(result as String) as Map<String, dynamic>;
        resultCompleter.complete(json);
      } catch (e) {
        resultCompleter.complete({});
      }
    }).catchError((e) {
      if (!tokenController.isClosed) {
        tokenController.addError(e);
        tokenController.close();
      }
      resultCompleter.complete({});
    });

    return (tokens: tokenController.stream, result: resultCompleter.future);
  }

  // ---- Engine health ----

  /// Get engine health info for settings screen.
  Future<Map<String, dynamic>> getEngineHealth() async {
    try {
      final result = await _method.invokeMethod('getEngineHealth');
      return jsonDecode(result as String) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  // ---- Helpers ----

  static InitState _parseState(String s) {
    switch (s) {
      case 'downloading':
        return InitState.downloading;
      case 'loading':
        return InitState.loading;
      case 'ready':
        return InitState.ready;
      case 'error':
        return InitState.error;
      default:
        return InitState.idle;
    }
  }
}

