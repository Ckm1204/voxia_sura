import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class VoxiaLlmService {
  VoxiaLlmService({required this.modelAssetPath, required this.systemPrompt});

  final String modelAssetPath;
  final String systemPrompt;

  static bool _gemmaInitialized = false;
  InferenceChat? _chat;

  Future<void> initialize() async {
    if (_chat != null) return;

    if (!_gemmaInitialized) {
      await FlutterGemma.initialize(enableWebCache: false);
      _gemmaInitialized = true;
    }

    const bundledName = 'gemma3-1B-it-int4.task';
    final candidates = <String>{
      modelAssetPath,
      'assets/models/gemma3-1B-it-int4.task',
      'packages/sura_voxia/assets/models/gemma3-1B-it-int4.task',
    };

    // Limpia cualquier copia previa corrupta en almacenamiento interno.
    try {
      final docs = await getApplicationDocumentsDirectory();
      final localModel = File('${docs.path}/$bundledName');
      if (await localModel.exists()) {
        await localModel.delete();
        debugPrint('VoxiaLlmService: borré copia previa en ${localModel.path}');
      }
    } catch (e) {
      debugPrint('VoxiaLlmService: no pude limpiar copia previa: $e');
    }

    Exception? lastError;

    for (final path in candidates) {
      try {
        debugPrint('VoxiaLlmService: installing model from asset $path');
        await FlutterGemma.installModel(
          modelType: ModelType.gemmaIt,
          fileType: ModelFileType.task,
        ).fromAsset(path).install();
        lastError = null;
        break;
      } catch (e) {
        lastError = e is Exception ? e : Exception('$e');
        debugPrint('VoxiaLlmService: install failed for $path -> $e');
      }
    }

    if (lastError != null) {
      throw lastError;
    }

    final inferenceModel = await FlutterGemma.getActiveModel(
      maxTokens: 1024,
      preferredBackend: PreferredBackend.gpu,
      supportImage: false,
    );

    _chat = await inferenceModel.createChat(
      temperature: 0.7,
      randomSeed: 1,
      topK: 40,
      topP: 0.95,
      tokenBuffer: 256,
      supportImage: false,
      supportsFunctionCalls: false,
      modelType: ModelType.gemmaIt,
    );

    if (systemPrompt.isNotEmpty) {
      await _chat!.addQuery(Message(text: systemPrompt, isUser: false));
    }
  }

  Future<String> generate(String userText) async {
    if (_chat == null) {
      throw StateError('LLM not initialized');
    }
    await _chat!.addQuery(Message(text: userText, isUser: true));
    final response = await _chat!.generateChatResponse();
    if (response is TextResponse) {
      return response.token;
    }
    if (response is FunctionCallResponse) {
      return '[Función no soportada: ${response.name}]';
    }
    debugPrint('Respuesta inesperada del modelo: $response');
    return '';
  }

  // No copy fallback: rely on packaged asset with package-prefixed path.
}