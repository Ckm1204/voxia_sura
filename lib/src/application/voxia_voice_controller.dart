import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../domain/entities/voxia_voice_state.dart';
import '../domain/ports/sound_player.dart';
import '../infrastructure/sound/audio_sound_player.dart';
import 'voxia_env_config.dart';
import 'voxia_llm_service.dart';

class VoxiaVoiceController extends ChangeNotifier {
  VoxiaVoiceController({
    required SpeechToText speech,
    required FlutterTts tts,
    required SoundPlayer soundPlayer,
    Duration silenceTimeout = const Duration(seconds: 5),
    Duration listenFor = const Duration(seconds: 60),
    String modelAssetPath = 'assets/models/gemma3-1B-it-int4.task',
  })  : _speech = speech,
        _tts = tts,
        _soundPlayer = soundPlayer,
        _silenceTimeout = silenceTimeout,
        _listenFor = listenFor,
        _modelAssetPath = modelAssetPath;

  factory VoxiaVoiceController.defaultInstance({
    Duration silenceTimeout = const Duration(seconds: 5),
    Duration listenFor = const Duration(seconds: 60),
  }) {
    return VoxiaVoiceController(
      speech: SpeechToText(),
      tts: FlutterTts(),
      soundPlayer: AudioSoundPlayer(),
      silenceTimeout: silenceTimeout,
      listenFor: listenFor,
    );
  }

  final SpeechToText _speech;
  final FlutterTts _tts;
  final SoundPlayer _soundPlayer;
  final Duration _silenceTimeout;
  final Duration _listenFor;
  final String _modelAssetPath;

  VoxiaVoiceState _state = VoxiaVoiceState.initial();
  VoxiaVoiceState get state => _state;

  VoxiaLlmService? _llm;
  Timer? _silenceTimer;

  Future<void> startSession() async {
    if (!_state.canStartSession) return;
    _updateState(_state.copyWith(
      status: VoxiaVoiceStatus.initializing,
      lastError: null,
    ));
    _appendLog('Iniciando sesión de voz a voz');
    try {
      final config = await VoxiaEnvConfig.load();
      await _initializeTts();
      await _initializeSpeech();
      await _initializeLlm(config.systemPrompt);
      _updateState(_state.copyWith(status: VoxiaVoiceStatus.ready));
    } catch (e, st) {
      _appendLog('Error al iniciar sesión: $e');
      debugPrint('Voxia startSession error: $e');
      debugPrint('$st');
      _updateState(_state.copyWith(
        status: VoxiaVoiceStatus.error,
        lastError: '$e',
      ));
    }
  }

  Future<void> startListening() async {
    if (!_state.canListen) return;
    _cancelSilenceTimer();
    _updateState(_state.copyWith(
      isListening: true,
      silenceStopPending: false,
      hasSpoken: false,
      status: VoxiaVoiceStatus.listening,
      lastError: null,
    ));
    _appendLog('Comenzando a escuchar');
    await _speech.listen(
      onResult: _onSpeechResult,
      listenFor: _listenFor,
      pauseFor: _silenceTimeout,
      partialResults: true,
      listenMode: ListenMode.dictation,
      localeId: _state.localeId.isEmpty ? null : _state.localeId,
    );
  }

  Future<void> stopListening() async {
    _appendLog('Parando escucha');
    _cancelSilenceTimer();
    await _speech.stop();
    _updateState(_state.copyWith(
      isListening: false,
      silenceStopPending: false,
      hasSpoken: false,
      status: VoxiaVoiceStatus.ready,
    ));
  }

  Future<void> speakText(String text) async {
    if (text.isEmpty) return;
    _updateState(_state.copyWith(isSpeaking: true));
    await _tts.setVolume(1.0);
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
    _appendLog('TTS: "$text"');
    await _tts.speak(text);
    _updateState(_state.copyWith(isSpeaking: false, status: VoxiaVoiceStatus.ready));
  }

  @override
  void dispose() {
    _cancelSilenceTimer();
    _tts.stop();
    _speech.stop();
    super.dispose();
  }

  Future<void> _initializeTts() async {
    await _tts.awaitSpeakCompletion(true);
    try {
      final languages = await _tts.getLanguages;
      final es = (languages as List<dynamic>?)
          ?.cast<String>()
          .firstWhere((lang) => lang.startsWith('es'), orElse: () => '');
      if (es != null && es.isNotEmpty) {
        await _tts.setLanguage(es);
        _appendLog('TTS idioma: $es');
      }
    } catch (_) {
      // ignore language errors
    }
  }

  Future<void> _initializeSpeech() async {
    final available = await _speech.initialize(
      onError: _onError,
      onStatus: _onStatus,
    );
    if (!available) {
      throw StateError('Micrófono no disponible o permiso denegado');
    }
    final locales = await _speech.locales();
    final locale = locales.firstWhere(
      (l) => l.localeId.startsWith('es'),
      orElse: () => locales.first,
    );
    _appendLog('Locale seleccionado: ${locale.localeId}');
    _updateState(_state.copyWith(
      speechEnabled: true,
      localeId: locale.localeId,
    ));
  }

  Future<void> _initializeLlm(String systemPrompt) async {
    _appendLog('Inicializando LLM local');
    _llm = VoxiaLlmService(
      modelAssetPath: _modelAssetPath,
      systemPrompt: systemPrompt,
    );
    await _llm!.initialize();
    _appendLog('LLM listo con prompt de sistema');
  }

  Future<void> _processRecognized(String text) async {
    if (_llm == null || text.trim().isEmpty) return;
    _updateState(_state.copyWith(
      isGenerating: true,
      modelResponse: '',
      recognizedText: text,
      status: VoxiaVoiceStatus.ready,
    ));
    _appendLog('Texto reconocido: "$text"');
    try {
      final response = await _llm!.generate(text);
      _appendLog('Respuesta LLM: "$response"');
      debugPrint('Voxia LLM response: $response');
      _updateState(_state.copyWith(
        modelResponse: response,
        isGenerating: false,
      ));
      await speakText(response);
    } catch (e) {
      _appendLog('Error generando respuesta: $e');
      _updateState(_state.copyWith(
        isGenerating: false,
        lastError: '$e',
        status: VoxiaVoiceStatus.error,
      ));
    }
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    final recognized = result.recognizedWords;
    _appendLog('Resultado parcial: $recognized');
    _cancelSilenceTimer();
    _updateState(_state.copyWith(
      recognizedText: recognized,
      hasSpoken: true,
      silenceStopPending: true,
    ));
    _silenceTimer = Timer(_silenceTimeout, () async {
      if (!_speech.isListening) return;
      _appendLog('Auto-stop por silencio ${_silenceTimeout.inSeconds}s');
      _updateState(_state.copyWith(silenceStopPending: false));
      await _speech.stop();
      _updateState(_state.copyWith(isListening: false));
    });

    if (result.finalResult) {
      _processRecognized(recognized);
    }
  }

  void _onStatus(String status) async {
    _appendLog('Estado de speech: $status');
    if (status == SpeechToText.listeningStatus || status == 'listening') {
      _cancelSilenceTimer();
      _updateState(_state.copyWith(
        isListening: true,
        status: VoxiaVoiceStatus.listening,
        silenceStopPending: false,
      ));
    } else if (status == SpeechToText.doneStatus || status == 'notListening') {
      if (!_state.hasSpoken) {
        _appendLog('No se detectó voz en la sesión');
        await _speech.stop();
      }
      _updateState(_state.copyWith(
        isListening: false,
        silenceStopPending: false,
        status: VoxiaVoiceStatus.ready,
      ));
    }
  }

  void _onError(SpeechRecognitionError error) {
    _appendLog('Error de speech: ${error.errorMsg}');
    _updateState(_state.copyWith(
      lastError: error.errorMsg,
      status: VoxiaVoiceStatus.error,
    ));
  }

  void _cancelSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = null;
  }

  void _appendLog(String message) {
    final timestamp = DateTime.now().toIso8601String();
    final updated = List<String>.from(_state.logLines)..add('$timestamp: $message');
    const maxLogLines = 120;
    if (updated.length > maxLogLines) {
      updated.removeRange(0, updated.length - maxLogLines);
    }
    _updateState(_state.copyWith(logLines: updated));
  }

  void _updateState(VoxiaVoiceState newState) {
    if (newState == _state) return;
    _state = newState;
    notifyListeners();
  }
}