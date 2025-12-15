import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:sura_voxia/sura_voxia.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('Unhandled platform error: $error\n$stack');
    return true;
  };

  VoxiaModelManager.initializeGemma();
  runApp(const VoxiaDemoApp());
}

class VoxiaDemoApp extends StatelessWidget {
  const VoxiaDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VOXIA',
      navigatorKey: navigatorKey,
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const VoxiaHomePage(title: 'VOXIA'),
    );
  }
}

class VoxiaHomePage extends StatefulWidget {
  const VoxiaHomePage({super.key, required this.title});

  final String title;

  @override
  State<VoxiaHomePage> createState() => _VoxiaHomePageState();
}

class _VoxiaHomePageState extends State<VoxiaHomePage> {
  late final VoxiaVoiceController _controller;
  late final VoxiaModelManager _modelManager;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = VoxiaVoiceController.defaultInstance();
    _modelManager = VoxiaModelManager();
  }

  @override
  void dispose() {
    _controller.dispose();
    _modelManager.dispose();
    super.dispose();
  }

  // Removed example FAB counter functionality.

  Future<void> _onInstallModelFromFile() async {
    final VoxiaModelActionResult result = await _modelManager.installFromFile();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<void> _onInstallDefaultModel() async {
    final VoxiaModelActionResult result =
        await _modelManager.installDefaultModel();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<void> _onCheckInstalled([String? assetKey]) async {
    final VoxiaModelActionResult result = await _modelManager
        .checkInstalledByKey(assetKey ?? _modelManager.defaultModelAssetKey);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  Widget _buildModelTestTab() {
    return const ModelTestScreen();
  }

  Widget _buildNurseAssistantTab() {
    return const _NurseAssistantTab();
  }

  Widget _buildModelsTab() {
    return AnimatedBuilder(
      animation: _modelManager,
      builder: (BuildContext context, _) {
        final bool isInstalling = _modelManager.isInstalling;
        final double progress = _modelManager.progress;
        final String defaultAssetKey = _modelManager.defaultModelAssetKey;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.file_upload),
                label: const Text('Instalar modelo desde archivo (.task)'),
                onPressed: isInstalling ? null : _onInstallModelFromFile,
              ),
              const SizedBox(height: 12),
              if (isInstalling) ...[
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 8),
                const Text('Instalando modelo...'),
              ],
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: isInstalling ? null : _onInstallDefaultModel,
                child: Text('Instalar ${defaultAssetKey.split('/').last}'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => _onCheckInstalled(defaultAssetKey),
                child: Text(
                  'Comprobar ${defaultAssetKey.split('/').last} instalado',
                ),
              ),
              if (isInstalling && progress > 0) ...[
                const SizedBox(height: 12),
                Text('Progreso: ${progress.toStringAsFixed(1)}%'),
              ],
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 8),
              // contador de ejemplo eliminado
            ],
          ),
        );
      },
    );
  }

  Widget _buildVoiceTab() {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final VoxiaVoiceState state = _controller.state;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed:
                        state.canStartSession ? _controller.startSession : null,
                    child: Text(switch (state.status) {
                      VoxiaVoiceStatus.initializing => 'Iniciando...',
                      VoxiaVoiceStatus.error => 'Reintentar sesión',
                      _ => 'Iniciar sesión',
                    }),
                  ),
                  ElevatedButton(
                    onPressed:
                        state.canListen
                            ? () {
                              if (state.isListening) {
                                _controller.stopListening();
                              } else {
                                _controller.startListening();
                              }
                            }
                            : null,
                    child: Text(state.isListening ? 'Parar' : 'Hablar'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _StatusRow(label: 'Estado sesión', value: state.status.name),
              _StatusRow(
                label: 'Speech habilitado',
                value: state.speechEnabled ? 'Sí' : 'No',
              ),
              _StatusRow(
                label: 'Escuchando',
                value: state.isListening ? 'Sí' : 'No',
              ),
              _StatusRow(
                label: 'Generando respuesta',
                value: state.isGenerating ? 'Sí' : 'No',
              ),
              _StatusRow(
                label: 'Hablando (TTS)',
                value: state.isSpeaking ? 'Sí' : 'No',
              ),
              _StatusRow(
                label: 'Locale',
                value: state.localeId.isEmpty ? 'unknown' : state.localeId,
              ),
              const SizedBox(height: 12),
              Text(
                'Reconocido:',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.black26),
                ),
                child: Text(
                  state.recognizedText.isEmpty
                      ? 'Sin texto aún'
                      : state.recognizedText,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Respuesta LLM:',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.black26),
                ),
                child: Text(
                  state.modelResponse.isEmpty
                      ? 'Sin respuesta todavía'
                      : state.modelResponse,
                ),
              ),
              if (state.lastError != null && state.lastError!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Error: ${state.lastError}',
                  style: const TextStyle(color: Colors.red),
                ),
              ],
              const Divider(height: 32),
              const Text('Log'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.black26),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    state.logAsText.isEmpty
                        ? 'Sin eventos todavía'
                        : state.logAsText,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      _buildNurseAssistantTab(),
      _buildModelTestTab(),
      _buildModelsTab(),
      _buildVoiceTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: tabs[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.white,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Colors.black54,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment),
            label: 'Cuestionario',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.play_arrow),
            label: 'Prueba modelo',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.storage), label: 'Modelos'),
          BottomNavigationBarItem(icon: Icon(Icons.mic), label: 'Sesión Voxia'),
        ],
      ),
      // FAB removed: example counter no longer used
    );
  }
}

class ModelTestScreen extends StatefulWidget {
  const ModelTestScreen({super.key});

  @override
  State<ModelTestScreen> createState() => _ModelTestScreenState();
}

class _LocalGemmaService {
  _LocalGemmaService(this._chat);

  final InferenceChat _chat;

  Future<Stream<ModelResponse>> processMessage(Message message) async {
    debugPrint('GemmaService: processing -> ${message.text}');
    await _chat.addQuery(message);
    return _chat.generateChatResponseAsync();
  }
}

enum _ConversationRole { user, assistant, system }

class _ConversationEntry {
  _ConversationEntry.user(this.text) : role = _ConversationRole.user;
  _ConversationEntry.assistant(this.text) : role = _ConversationRole.assistant;
  _ConversationEntry.system(this.text) : role = _ConversationRole.system;

  final _ConversationRole role;
  String text;
}

class _PendingThinking {
  final StringBuffer _buffer = StringBuffer();

  void add(String chunk) => _buffer.write(chunk);

  String get value => _buffer.toString();
}

class _ModelTestScreenState extends State<ModelTestScreen> {
  final TextEditingController _promptController = TextEditingController(
    text: 'Hello!',
  );
  String _responseText = '';
  bool _isRunning = false;
  StreamSubscription<ModelResponse>? _respSub;

  final ScrollController _conversationScrollController = ScrollController();
  InferenceModel? _cachedModel;
  InferenceChat? _chat;
  final List<_ConversationEntry> _conversation = [];
  int? _activeThinkingIndex;
  _PendingThinking? _pendingThinking;
  bool _retryingAfterEmpty = false;

  bool _isInstallingLocal = false;
  double _progressLocal = 0.0;
  late final VoxiaModelManager _modelManager;

  @override
  void initState() {
    super.initState();
    _modelManager = VoxiaModelManager();
    _modelManager.addListener(_handleModelManagerUpdate);
  }

  @override
  void dispose() {
    _promptController.dispose();
    _respSub?.cancel();
    _conversationScrollController.dispose();
    _modelManager.removeListener(_handleModelManagerUpdate);
    _modelManager.dispose();
    super.dispose();
  }

  void _handleModelManagerUpdate() {
    if (!mounted) return;
    setState(() {
      _isInstallingLocal = _modelManager.isInstalling;
      _progressLocal = _modelManager.progress;
    });
  }

  Future<void> _resetChatSession({
    bool clearHistory = false,
    bool notify = false,
  }) async {
    await _respSub?.cancel();
    _respSub = null;
    _chat = null;
    _cachedModel = null;

    if (!mounted) return;
    if (clearHistory) {
      setState(() => _conversation.clear());
    }
    if (notify) {
      setState(
        () =>
            _conversation.add(_ConversationEntry.system('Sesión reiniciada.')),
      );
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_conversationScrollController.hasClients) return;
      _conversationScrollController.animateTo(
        _conversationScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _appendSystemMessage(String text) {
    if (!mounted) return;
    setState(() => _conversation.add(_ConversationEntry.system(text)));
    _scrollToBottom();
  }

  Future<InferenceChat> _ensureChatInitialized() async {
    if (_chat != null) return _chat!;
    _cachedModel = await FlutterGemma.getActiveModel(
      maxTokens: 2048,
      preferredBackend: PreferredBackend.cpu,
    );
    _chat = await _cachedModel!.createChat();
    return _chat!;
  }

  int _createAssistantEntry() {
    if (!mounted) return -1;
    int index = -1;
    setState(() {
      _conversation.add(_ConversationEntry.assistant(''));
      index = _conversation.length - 1;
    });
    _scrollToBottom();
    return index;
  }

  Future<void> _startStreamingResponse({
    required InferenceChat chat,
    required int responseIndex,
    required Message sourceMessage,
  }) async {
    final service = _LocalGemmaService(chat);
    final stream = await service.processMessage(sourceMessage);

    await _respSub?.cancel();
    _respSub = stream.listen(
      (ModelResponse resp) {
        debugPrint('Stream event: type=${resp.runtimeType} payload=$resp');
        if (!mounted ||
            responseIndex < 0 ||
            responseIndex >= _conversation.length)
          return;

        if (resp is TextResponse) {
          if (resp.token.isEmpty) return;
          setState(() => _conversation[responseIndex].text += resp.token);
        } else if (resp is ThinkingResponse) {
          _pendingThinking ??= _PendingThinking();
          _pendingThinking!.add(resp.content);

          if (_activeThinkingIndex == null) {
            setState(() {
              _conversation.add(
                _ConversationEntry.system('[Pensando]\n${resp.content}'),
              );
              _activeThinkingIndex = _conversation.length - 1;
            });
          } else {
            setState(
              () => _conversation[_activeThinkingIndex!].text += resp.content,
            );
          }
        } else if (resp is FunctionCallResponse) {
          final serializedArgs = resp.args.entries
              .map((e) => '${e.key}: ${e.value}')
              .join(', ');
          setState(() {
            _conversation.add(
              _ConversationEntry.system(
                '🔧 Llamada a función ${resp.name} ($serializedArgs)',
              ),
            );
          });
        }
        _scrollToBottom();
      },
      onError: (error) {
        if (!mounted) return;
        final message = '[Error streaming response] $error';
        if (responseIndex >= 0 && responseIndex < _conversation.length) {
          setState(() => _conversation[responseIndex].text += '\n$message');
        } else {
          _appendSystemMessage(message);
        }
        setState(() => _isRunning = false);
      },
      onDone: () async {
        if (!mounted) return;
        final entry = _conversation[responseIndex];

        if (entry.text.trim().isEmpty) {
          setState(() => entry.text = '[La respuesta llegó vacía.]');
          if (_retryingAfterEmpty) {
            _appendSystemMessage(
              'Reintento fallido. Por favor intenta de nuevo manualmente.',
            );
            setState(() => _isRunning = false);
            _retryingAfterEmpty = false;
            return;
          }

          _retryingAfterEmpty = true;
          await _retryWithFreshChat(sourceMessage, responseIndex);
          return;
        }

        if (_activeThinkingIndex != null) {
          setState(() {
            _conversation[_activeThinkingIndex!].text +=
                '\n[Fin del pensamiento]';
            _activeThinkingIndex = null;
          });
        }
        _pendingThinking = null;
        _retryingAfterEmpty = false;
        setState(() => _isRunning = false);
      },
    );
  }

  Future<void> _retryWithFreshChat(
    Message originalMsg,
    int responseIndex,
  ) async {
    await _respSub?.cancel();
    _respSub = null;

    setState(() {
      _activeThinkingIndex = null;
      if (responseIndex < _conversation.length) {
        _conversation.removeAt(responseIndex);
      }
    });

    _appendSystemMessage(
      'La respuesta llegó vacía, reintentando con una sesión nueva...',
    );

    try {
      final newModel = await FlutterGemmaPlugin.instance.createModel(
        modelType: ModelType.gemmaIt,
        preferredBackend: PreferredBackend.cpu,
        maxTokens: 2048,
      );
      _cachedModel = newModel;
      _chat = await newModel.createChat();
      final retryIndex = _createAssistantEntry();
      await _startStreamingResponse(
        chat: _chat!,
        responseIndex: retryIndex,
        sourceMessage: originalMsg,
      );
    } catch (e) {
      setState(() {
        _isRunning = false;
        _conversation.add(
          _ConversationEntry.system(
            'No fue posible reintentar la respuesta: $e',
          ),
        );
      });
    }
  }

  Future<bool> _handleNoActiveModel(String prompt) async {
    _appendSystemMessage(
      'No hay modelo activo: intentando crear uno en CPU...',
    );
    try {
      final legacyModel = await FlutterGemmaPlugin.instance.createModel(
        modelType: ModelType.gemmaIt,
        preferredBackend: PreferredBackend.cpu,
        maxTokens: 2048,
      );
      _cachedModel = legacyModel;
      _chat = await legacyModel.createChat();
      await _runWithChat(_chat!, prompt);
      return true;
    } catch (e2) {
      _appendSystemMessage('No fue posible crear el modelo en CPU: $e2');
      if (mounted) {
        setState(() {
          _isRunning = false;
          _responseText =
              'No hay un modelo activo. Instala uno en la pestaña Modelos o usa el paquete por defecto.';
        });
      }
      final installed = await _promptInstallDefaultModel();
      if (installed) {
        await _resetChatSession(clearHistory: false);
        await Future.delayed(const Duration(milliseconds: 200));
        await _runModel(promptOverride: prompt, appendUserMessage: false);
      }
      return false;
    }
  }

  Future<bool> _installDefaultAssetAndSetActive() async {
    if (mounted) {
      setState(() {
        _responseText = 'Instalando modelo por defecto...';
      });
    }

    final VoxiaModelActionResult result =
        await _modelManager.installDefaultModel();
    if (!mounted) {
      return result.success;
    }

    if (result.success) {
      await _resetChatSession(clearHistory: true, notify: true);
      setState(() {
        _responseText = 'Modelo instalado y activado correctamente.';
      });
    } else {
      setState(() {
        _responseText = result.message;
      });
    }

    return result.success;
  }

  Future<bool> _promptInstallDefaultModel() async {
    if (!mounted) return false;
    final choice = await showDialog<String?>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('No hay modelo activo'),
            content: const Text(
              'No se ha encontrado un modelo activo. ¿Deseas instalar el modelo empaquetado gemma3-1B-it-int4.task ahora?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop('cancel'),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop('models'),
                child: const Text('Ir a Modelos'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop('install'),
                child: const Text('Instalar ahora'),
              ),
            ],
          ),
    );

    if (!mounted) return false;

    if (choice == 'install') {
      return await _installDefaultAssetAndSetActive();
    } else if (choice == 'models') {
      try {
        final homeState =
            context.findAncestorStateOfType<_VoxiaHomePageState>();
        if (homeState != null) {
          homeState._onItemTapped(1);
        }
      } catch (_) {}
      return false;
    }
    return false;
  }

  Future<void> _runWithChat(InferenceChat chat, String prompt) async {
    final userMessage = Message.text(text: prompt, isUser: true);
    final responseIndex = _createAssistantEntry();
    await _startStreamingResponse(
      chat: chat,
      responseIndex: responseIndex,
      sourceMessage: userMessage,
    );
  }

  Future<void> _runModel({
    String? promptOverride,
    bool appendUserMessage = true,
  }) async {
    final rawPrompt = promptOverride ?? _promptController.text;
    final prompt = rawPrompt.trim();
    if (prompt.isEmpty) return;

    if (appendUserMessage) {
      _promptController.clear();
    }

    if (mounted) {
      setState(() {
        _responseText = '';
        _isRunning = true;
        if (appendUserMessage) {
          _conversation.add(_ConversationEntry.user(prompt));
        }
      });
      if (appendUserMessage) {
        _scrollToBottom();
      }
    }

    try {
      final chat = await _ensureChatInitialized();
      await _runWithChat(chat, prompt);
    } catch (e) {
      final errStr = e.toString();
      if (errStr.contains('No active inference model set')) {
        final handled = await _handleNoActiveModel(prompt);
        if (!handled && mounted) {
          setState(() => _isRunning = false);
        }
        return;
      }

      if (mounted) {
        setState(() {
          _responseText = 'Error ejecutando el modelo: $e';
          _isRunning = false;
        });
      }
      _appendSystemMessage('Error ejecutando el modelo: $e');
    }
  }

  Future<void> _safeVerifyActivation() async {
    setState(() {
      _responseText = 'Verificando activación (CPU)...';
      _isRunning = true;
    });

    try {
      await FlutterGemma.getActiveModel(
        maxTokens: 2048,
        preferredBackend: PreferredBackend.cpu,
      ).timeout(const Duration(seconds: 20));

      if (mounted) {
        setState(() {
          _responseText =
              'Verificación completa: modelo inicializado correctamente (CPU).';
        });
      }
      return;
    } catch (e) {
      if (e is TimeoutException) {
        if (mounted) {
          setState(() {
            _responseText =
                'Tiempo de espera en inicialización del modelo activo. Intentando fallback (legacy createModel) en CPU...';
          });
        }

        try {
          await FlutterGemmaPlugin.instance
              .createModel(
                modelType: ModelType.gemmaIt,
                preferredBackend: PreferredBackend.cpu,
                maxTokens: 2048,
              )
              .timeout(const Duration(seconds: 30));

          if (mounted) {
            setState(() {
              _responseText =
                  'Fallback exitoso: modelo creado en CPU con API legacy.';
            });
          }
          return;
        } catch (e2) {
          if (!mounted) return;
          final choice = await showDialog<String?>(
            context: context,
            builder:
                (ctx) => AlertDialog(
                  title: const Text('No se pudo inicializar el modelo'),
                  content: const Text(
                    'La verificación tardó demasiado y no fue posible crear un modelo en CPU. ¿Deseas instalar el modelo empaquetado gemma3-1B-it-int4.task ahora?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop('cancel'),
                      child: const Text('Cancelar'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop('models'),
                      child: const Text('Ir a Modelos'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop('install'),
                      child: const Text('Instalar ahora'),
                    ),
                  ],
                ),
          );

          if (choice == 'install') {
            final ok = await _installDefaultAssetAndSetActive();
            if (ok) {
              await Future.delayed(const Duration(milliseconds: 200));
              await _safeVerifyActivation();
              return;
            } else {
              if (mounted)
                setState(
                  () =>
                      _responseText =
                          'Instalación intentada pero la activación falló.',
                );
              return;
            }
          } else if (choice == 'models') {
            if (mounted) {
              final homeState =
                  context.findAncestorStateOfType<_VoxiaHomePageState>();
              if (homeState != null) homeState._onItemTapped(1);
              setState(
                () =>
                    _responseText =
                        'Ve a la pestaña Modelos para instalar manualmente.',
              );
            }
            return;
          } else {
            if (mounted)
              setState(
                () => _responseText = 'Verificación cancelada por el usuario.',
              );
            return;
          }
        }
      }

      final msg = e.toString();
      if (msg.contains('No active inference model set')) {
        if (!mounted) return;
        final choice = await showDialog<String?>(
          context: context,
          builder:
              (ctx) => AlertDialog(
                title: const Text('No hay modelo activo'),
                content: const Text(
                  'No se encontró un modelo activo. ¿Deseas instalar el modelo por defecto gemma3-1B-it-int4.task ahora?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop('cancel'),
                    child: const Text('Cancelar'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop('models'),
                    child: const Text('Ir a Modelos'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop('install'),
                    child: const Text('Instalar ahora'),
                  ),
                ],
              ),
        );

        if (choice == 'install') {
          final ok = await _installDefaultAssetAndSetActive();
          if (ok) {
            await Future.delayed(const Duration(milliseconds: 200));
            await _safeVerifyActivation();
            return;
          } else {
            if (mounted)
              setState(
                () =>
                    _responseText =
                        'Instalación intentada pero la activación falló.',
              );
            return;
          }
        } else if (choice == 'models') {
          if (mounted) {
            final homeState =
                context.findAncestorStateOfType<_VoxiaHomePageState>();
            if (homeState != null) homeState._onItemTapped(1);
            setState(
              () =>
                  _responseText =
                      'Ve a la pestaña Modelos para instalar manualmente.',
            );
          }
          return;
        } else {
          if (mounted)
            setState(
              () => _responseText = 'Verificación cancelada por el usuario.',
            );
          return;
        }
      }

      if (mounted) setState(() => _responseText = 'Verificación fallida: $e');
    } finally {
      setState(() {
        _isRunning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Flexible(
            fit: FlexFit.loose,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Prueba Modern API (usa el modelo activo):',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _promptController,
                    maxLines: 6,
                    minLines: 1,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Prompt',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.play_arrow),
                          label: Text(
                            _isRunning
                                ? 'Corriendo...'
                                : 'Enviar y generar respuesta',
                          ),
                          onPressed:
                              _isRunning || _isInstallingLocal
                                  ? null
                                  : _runModel,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed:
                              _isRunning || _isInstallingLocal
                                  ? null
                                  : _safeVerifyActivation,
                          child: const Text(
                            'Verificar activación segura (CPU)',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_isInstallingLocal) ...[
                    LinearProgressIndicator(value: _progressLocal / 100.0),
                    const SizedBox(height: 8),
                    Text(
                      'Instalando modelo por defecto: ${_progressLocal.toStringAsFixed(1)}%',
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_responseText.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(_responseText),
                    ),
                  Expanded(
                    child:
                        _conversation.isEmpty
                            ? const Center(
                              child: Text(
                                'Aquí aparecerá la conversación con el modelo.',
                              ),
                            )
                            : ListView.builder(
                              controller: _conversationScrollController,
                              itemCount: _conversation.length,
                              itemBuilder: (context, index) {
                                final entry = _conversation[index];
                                final alignment =
                                    entry.role == _ConversationRole.user
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft;
                                final bubbleColor =
                                    entry.role == _ConversationRole.user
                                        ? Theme.of(
                                          context,
                                        ).colorScheme.primaryContainer
                                        : entry.role == _ConversationRole.system
                                        ? Colors.amber.shade100
                                        : Colors.grey.shade200;
                                final textStyle = TextStyle(
                                  color:
                                      entry.role == _ConversationRole.user
                                          ? Theme.of(
                                            context,
                                          ).colorScheme.onPrimaryContainer
                                          : Colors.black87,
                                  fontStyle:
                                      entry.role == _ConversationRole.system
                                          ? FontStyle.italic
                                          : FontStyle.normal,
                                );

                                return Align(
                                  alignment: alignment,
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: bubbleColor,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(entry.text, style: textStyle),
                                  ),
                                );
                              },
                            ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, overflow: TextOverflow.ellipsis, maxLines: 1),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _NurseAssistantTab extends StatefulWidget {
  const _NurseAssistantTab();

  @override
  State<_NurseAssistantTab> createState() => _NurseAssistantTabState();
}

class _NurseAssistantTabState extends State<_NurseAssistantTab> {
  late final VoxiaQuestionnaireManager _manager;

  @override
  void initState() {
    super.initState();
    _manager = VoxiaQuestionnaireManager();
  }

  @override
  void dispose() {
    _manager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _manager,
      builder: (BuildContext context, _) {
        final VoxiaQuestionnaireState state = _manager.state;
        final VoxiaSessionState voiceState = state.voiceState;
        final ThemeData theme = Theme.of(context);

        return Scaffold(
          appBar: AppBar(title: const Text('Asistente de curaciones Voxia')),
          body: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        _StatusChip(
                          label: 'Sesion',
                          value:
                              state.sessionActive
                                  ? 'Activa'
                                  : state.sessionCompleted
                                  ? 'Completa'
                                  : 'Inactiva',
                        ),
                        _StatusChip(
                          label: 'Motor voz',
                          value: voiceState.status.name,
                        ),
                        if (voiceState.isListening)
                          const _StatusChip(
                            label: 'Escucha',
                            value: 'Capturando',
                          ),
                        if (state.awaitingAnswer)
                          const _StatusChip(
                            label: 'Estado',
                            value: 'Esperando respuesta',
                          ),
                        if (state.processingAnswer)
                          const _StatusChip(
                            label: 'Estado',
                            value: 'Procesando',
                          ),
                        if (state.pendingVoiceStart)
                          const _StatusChip(
                            label: 'Conexion',
                            value: 'Iniciando Voxia',
                          ),
                      ],
                    ),
                    if (voiceState.recognizedText.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Transcripcion actual',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(voiceState.recognizedText),
                          ],
                        ),
                      ),
                    if (state.lastError != null && state.lastError!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          state.lastError!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child:
                    state.messages.isEmpty
                        ? const Center(
                          child: Text(
                            'Aun no hay mensajes. Inicia la sesion para hablar con Voxia.',
                          ),
                        )
                        : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: state.messages.length,
                          itemBuilder: (BuildContext context, int index) {
                            final VoxiaQuestionMessage message =
                                state.messages[index];
                            final bool isAssistant =
                                message.role ==
                                VoxiaQuestionMessageRole.assistant;
                            final Color background =
                                isAssistant
                                    ? theme.colorScheme.primary.withOpacity(0.1)
                                    : theme.colorScheme.secondaryContainer;

                            return Align(
                              alignment:
                                  isAssistant
                                      ? Alignment.centerLeft
                                      : Alignment.centerRight,
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                constraints: const BoxConstraints(
                                  maxWidth: 320,
                                ),
                                decoration: BoxDecoration(
                                  color: background,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  message.text,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                            );
                          },
                        ),
              ),
              if (state.summary.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Resumen de respuestas',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          SelectableText(state.summary),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          bottomNavigationBar: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed:
                        state.canStartSession
                            ? () => _manager.startSession()
                            : null,
                    icon: const Icon(Icons.mic_none),
                    label: const Text('Iniciar Voxia'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        state.canCloseSession
                            ? () => _manager.closeSession()
                            : null,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Detener'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.grey.shade200,
      ),
      child: Text('$label: $value'),
    );
  }
}
