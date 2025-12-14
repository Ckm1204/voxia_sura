import 'package:flutter/foundation.dart';

enum VoxiaVoiceStatus { loggedOut, initializing, ready, listening, speaking, error }

class VoxiaVoiceState {
  const VoxiaVoiceState({
    required this.status,
    required this.speechEnabled,
    required this.isListening,
    required this.isGenerating,
    required this.isSpeaking,
    required this.silenceStopPending,
    required this.hasSpoken,
    required this.localeId,
    required this.recognizedText,
    required this.modelResponse,
    required this.logLines,
    this.lastError,
  });

  factory VoxiaVoiceState.initial() {
    return const VoxiaVoiceState(
      status: VoxiaVoiceStatus.loggedOut,
      speechEnabled: false,
      isListening: false,
      isGenerating: false,
      isSpeaking: false,
      silenceStopPending: false,
      hasSpoken: false,
      localeId: '',
      recognizedText: '',
      modelResponse: '',
      logLines: <String>[],
      lastError: null,
    );
  }

  final VoxiaVoiceStatus status;
  final bool speechEnabled;
  final bool isListening;
  final bool isGenerating;
  final bool isSpeaking;
  final bool silenceStopPending;
  final bool hasSpoken;
  final String localeId;
  final String recognizedText;
  final String modelResponse;
  final List<String> logLines;
  final String? lastError;

  bool get canStartSession => status == VoxiaVoiceStatus.loggedOut || status == VoxiaVoiceStatus.error;
  bool get canListen => status == VoxiaVoiceStatus.ready && speechEnabled && !isGenerating && !isSpeaking;
  String get logAsText => logLines.join('\n');

  VoxiaVoiceState copyWith({
    VoxiaVoiceStatus? status,
    bool? speechEnabled,
    bool? isListening,
    bool? isGenerating,
    bool? isSpeaking,
    bool? silenceStopPending,
    bool? hasSpoken,
    String? localeId,
    String? recognizedText,
    String? modelResponse,
    List<String>? logLines,
    String? lastError,
  }) {
    return VoxiaVoiceState(
      status: status ?? this.status,
      speechEnabled: speechEnabled ?? this.speechEnabled,
      isListening: isListening ?? this.isListening,
      isGenerating: isGenerating ?? this.isGenerating,
      isSpeaking: isSpeaking ?? this.isSpeaking,
      silenceStopPending: silenceStopPending ?? this.silenceStopPending,
      hasSpoken: hasSpoken ?? this.hasSpoken,
      localeId: localeId ?? this.localeId,
      recognizedText: recognizedText ?? this.recognizedText,
      modelResponse: modelResponse ?? this.modelResponse,
      logLines: logLines ?? this.logLines,
      lastError: lastError,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VoxiaVoiceState &&
        other.status == status &&
        other.speechEnabled == speechEnabled &&
        other.isListening == isListening &&
        other.isGenerating == isGenerating &&
        other.isSpeaking == isSpeaking &&
        other.silenceStopPending == silenceStopPending &&
        other.hasSpoken == hasSpoken &&
        other.localeId == localeId &&
        other.recognizedText == recognizedText &&
        other.modelResponse == modelResponse &&
        listEquals(other.logLines, logLines) &&
        other.lastError == lastError;
  }

  @override
  int get hashCode => Object.hash(
        status,
        speechEnabled,
        isListening,
        isGenerating,
        isSpeaking,
        silenceStopPending,
        hasSpoken,
        localeId,
        recognizedText,
        modelResponse,
        Object.hashAll(logLines),
        lastError,
      );
}