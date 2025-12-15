import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../domain/entities/voxia_session_state.dart';
import '../domain/ports/sound_player.dart';
import '../infrastructure/sound/audio_sound_player.dart';

class VoxiaController extends ChangeNotifier {
  VoxiaController({
    required SpeechToText speech,
    required FlutterTts tts,
    required SoundPlayer soundPlayer,
    Duration silenceTimeout = const Duration(seconds: 5),
    Duration listenFor = const Duration(seconds: 60),
  })  : _speech = speech,
        _tts = tts,
        _soundPlayer = soundPlayer,
        _silenceTimeout = silenceTimeout,
        _listenFor = listenFor;

  factory VoxiaController.defaultInstance({
    Duration silenceTimeout = const Duration(seconds: 5),
    Duration listenFor = const Duration(seconds: 60),
  }) {
    return VoxiaController(
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

  VoxiaSessionState _state = VoxiaSessionState.initial();
  VoxiaSessionState get state => _state;

  Timer? _silenceTimer;

  Future<void> login() async {
    if (_state.status == SessionStatus.initializing) return;
    _updateState(_state.copyWith(status: SessionStatus.initializing, lastError: null));
    _appendLog('Iniciando sesión de voz');
    try {
      await _initializeTts();
      await _initializeSpeech();
    } catch (e) {
      _appendLog('Error al iniciar: $e');
      _updateState(_state.copyWith(status: SessionStatus.error, lastError: '$e'));
    }
  }

  Future<void> startListening() async {
    if (!_state.canListen) return;
    _cancelSilenceTimer();
    _updateState(_state.copyWith(
      isListening: true,
      silenceStopPending: false,
      hasSpoken: false,
      lastError: null,
    ));
    _appendLog('start listening');
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
    _appendLog('stop listening');
    _cancelSilenceTimer();
    await _speech.stop();
    _updateState(_state.copyWith(
      isListening: false,
      silenceStopPending: false,
      hasSpoken: false,
    ));
  }

  Future<void> speakText([String? text]) async {
    final content = text?.trim().isNotEmpty == true ? text!.trim() : _state.recognizedText;
    if (content.isEmpty) return;
    await _tts.setVolume(1.0);
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
    _appendLog('tts speak: "$content"');
    await _tts.speak(content);
  }

  Future<void> playNotification({String assetPath = 'sounds/notification.m4r'}) async {
    _appendLog('play sound: $assetPath');
    await _soundPlayer.play(assetPath);
  }

  Future<void> logout() async {
    if (_state.status == SessionStatus.loggedOut) return;
    _appendLog('Cerrando sesión de voz');
    _cancelSilenceTimer();
    try {
      await _speech.stop();
    } catch (_) {
      // ignore stop errors
    }
    try {
      await _tts.stop();
    } catch (_) {
      // ignore stop errors
    }
    _updateState(VoxiaSessionState.initial());
  }

  void clearRecognizedText() {
    if (_state.recognizedText.isEmpty && !_state.hasSpoken) return;
    _appendLog('Clearing recognized text');
    _updateState(_state.copyWith(recognizedText: '', hasSpoken: false));
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
    final availableLangs = await _tts.getLanguages;
    final String? es = (availableLangs as List<dynamic>?)
        ?.cast<String>()
        .firstWhere((lang) => lang.startsWith('es'), orElse: () => '');
    if (es != null && es.isNotEmpty) {
      await _tts.setLanguage(es);
      _appendLog('TTS language set to $es');
    }
  }

  Future<void> _initializeSpeech() async {
    final bool available = await _speech.initialize(
      onError: _onError,
      onStatus: _onStatus,
    );

    if (!available) {
      _appendLog('Speech not available or permission denied');
      _updateState(_state.copyWith(
        speechEnabled: false,
        status: SessionStatus.error,
        lastError: 'Speech not available or permission denied',
      ));
      return;
    }

    final locales = await _speech.locales();
    final locale = locales.firstWhere(
      (l) => l.localeId.startsWith('es'),
      orElse: () => locales.first,
    );
    _appendLog('Locale selected: ${locale.localeId}');
    _updateState(_state.copyWith(
      status: SessionStatus.ready,
      speechEnabled: true,
      localeId: locale.localeId,
      lastError: null,
    ));
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    final recognized = result.recognizedWords;
    _appendLog('Speech result: $recognized');
    _cancelSilenceTimer();
    _updateState(_state.copyWith(
      recognizedText: recognized,
      hasSpoken: true,
      silenceStopPending: true,
    ));
    _silenceTimer = Timer(_silenceTimeout, () async {
      if (!_speech.isListening) return;
      _appendLog('Silence auto-stop after ${_silenceTimeout.inSeconds}s');
      _updateState(_state.copyWith(silenceStopPending: false));
      await _speech.stop();
      _updateState(_state.copyWith(isListening: false));
    });
  }

  void _onStatus(String status) async {
    _appendLog('Speech status: $status');
    if (status == SpeechToText.listeningStatus || status == 'listening') {
      _cancelSilenceTimer();
      _updateState(_state.copyWith(isListening: true, silenceStopPending: false));
    } else if (status == SpeechToText.doneStatus || status == 'notListening') {
      if (!_state.hasSpoken) {
        _appendLog('Stopping: no user speech detected during session');
        await _speech.stop();
      }
      _updateState(_state.copyWith(isListening: false, silenceStopPending: false));
    }
  }

  void _onError(SpeechRecognitionError errorNotification) {
    _appendLog('Error: ${errorNotification.errorMsg}');
    _updateState(_state.copyWith(lastError: errorNotification.errorMsg));
  }

  void _cancelSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = null;
  }

  void _appendLog(String message) {
    final timestamp = DateTime.now().toIso8601String();
    final updated = List<String>.from(_state.logLines)..add('$timestamp: $message');
    const maxLogLines = 80;
    if (updated.length > maxLogLines) {
      updated.removeRange(0, updated.length - maxLogLines);
    }
    _updateState(_state.copyWith(logLines: updated));
  }

  void _updateState(VoxiaSessionState newState) {
    if (newState == _state) return;
    _state = newState;
    notifyListeners();
  }
}