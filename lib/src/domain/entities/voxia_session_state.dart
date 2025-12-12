import 'package:flutter/foundation.dart';

enum SessionStatus { loggedOut, initializing, ready, error }

class VoxiaSessionState {
  const VoxiaSessionState({
    required this.status,
    required this.speechEnabled,
    required this.isListening,
    required this.silenceStopPending,
    required this.hasSpoken,
    required this.localeId,
    required this.recognizedText,
    required this.logLines,
    this.lastError,
  });

  factory VoxiaSessionState.initial() {
    return const VoxiaSessionState(
      status: SessionStatus.loggedOut,
      speechEnabled: false,
      isListening: false,
      silenceStopPending: false,
      hasSpoken: false,
      localeId: '',
      recognizedText: '',
      logLines: <String>[],
      lastError: null,
    );
  }

  final SessionStatus status;
  final bool speechEnabled;
  final bool isListening;
  final bool silenceStopPending;
  final bool hasSpoken;
  final String localeId;
  final String recognizedText;
  final List<String> logLines;
  final String? lastError;

  bool get canListen => status == SessionStatus.ready && speechEnabled;

  String get logAsText => logLines.join('\n');

  VoxiaSessionState copyWith({
    SessionStatus? status,
    bool? speechEnabled,
    bool? isListening,
    bool? silenceStopPending,
    bool? hasSpoken,
    String? localeId,
    String? recognizedText,
    List<String>? logLines,
    String? lastError,
  }) {
    return VoxiaSessionState(
      status: status ?? this.status,
      speechEnabled: speechEnabled ?? this.speechEnabled,
      isListening: isListening ?? this.isListening,
      silenceStopPending: silenceStopPending ?? this.silenceStopPending,
      hasSpoken: hasSpoken ?? this.hasSpoken,
      localeId: localeId ?? this.localeId,
      recognizedText: recognizedText ?? this.recognizedText,
      logLines: logLines ?? this.logLines,
      lastError: lastError ?? this.lastError,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VoxiaSessionState &&
        other.status == status &&
        other.speechEnabled == speechEnabled &&
        other.isListening == isListening &&
        other.silenceStopPending == silenceStopPending &&
        other.hasSpoken == hasSpoken &&
        other.localeId == localeId &&
        other.recognizedText == recognizedText &&
        listEquals(other.logLines, logLines) &&
        other.lastError == lastError;
  }

  @override
  int get hashCode => Object.hash(
        status,
        speechEnabled,
        isListening,
        silenceStopPending,
        hasSpoken,
        localeId,
        recognizedText,
        Object.hashAll(logLines),
        lastError,
      );
}