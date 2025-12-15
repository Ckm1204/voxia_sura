import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/entities/voxia_session_state.dart';
import '../voxia_controller.dart';

enum QuestionFieldType {
  text,
  longText,
  date,
  number,
  selection,
  boolean,
  booleanText,
  range,
}

class QuestionnaireQuestion {
  const QuestionnaireQuestion({
    required this.id,
    required this.label,
    required this.prompt,
    required this.type,
    this.options = const <String>[],
    this.unit,
    this.min,
    this.max,
  });

  factory QuestionnaireQuestion.fromJson(Map<String, dynamic> json) {
    final List<dynamic>? rawOptions = json['options'] as List<dynamic>?;
    return QuestionnaireQuestion(
      id: json['id'] as String,
      label: json['label'] as String,
      prompt: json['prompt'] as String,
      type: _questionFieldTypeFromString(json['type'] as String),
      options:
          rawOptions == null
              ? const <String>[]
              : List<String>.unmodifiable(
                rawOptions.map((dynamic item) => item.toString()),
              ),
      unit: json['unit'] as String?,
      min: json['min'] is num ? json['min'] as num : null,
      max: json['max'] is num ? json['max'] as num : null,
    );
  }

  final String id;
  final String label;
  final String prompt;
  final QuestionFieldType type;
  final List<String> options;
  final String? unit;
  final num? min;
  final num? max;
}

class QuestionnaireSection {
  const QuestionnaireSection({
    required this.id,
    required this.displayName,
    required this.questions,
  });

  factory QuestionnaireSection.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawQuestions = json['questions'] as List<dynamic>;
    return QuestionnaireSection(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      questions: List<QuestionnaireQuestion>.unmodifiable(
        rawQuestions
            .map(
              (dynamic item) =>
                  QuestionnaireQuestion.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
      ),
    );
  }

  final String id;
  final String displayName;
  final List<QuestionnaireQuestion> questions;
}

enum VoxiaQuestionMessageRole { assistant, patient }

class VoxiaQuestionMessage {
  const VoxiaQuestionMessage._(this.text, this.role);

  const VoxiaQuestionMessage.assistant(String text)
    : this._(text, VoxiaQuestionMessageRole.assistant);
  const VoxiaQuestionMessage.patient(String text)
    : this._(text, VoxiaQuestionMessageRole.patient);

  final String text;
  final VoxiaQuestionMessageRole role;
}

class VoxiaQuestionnaireState {
  const VoxiaQuestionnaireState({
    required this.voiceState,
    required this.messages,
    required this.summary,
    required this.sessionActive,
    required this.sessionCompleted,
    required this.pendingVoiceStart,
    required this.awaitingAnswer,
    required this.processingAnswer,
    required this.lastError,
  });

  factory VoxiaQuestionnaireState.initial(VoxiaSessionState voiceState) {
    return VoxiaQuestionnaireState(
      voiceState: voiceState,
      messages: const <VoxiaQuestionMessage>[],
      summary: '',
      sessionActive: false,
      sessionCompleted: false,
      pendingVoiceStart: false,
      awaitingAnswer: false,
      processingAnswer: false,
      lastError: null,
    );
  }

  final VoxiaSessionState voiceState;
  final List<VoxiaQuestionMessage> messages;
  final String summary;
  final bool sessionActive;
  final bool sessionCompleted;
  final bool pendingVoiceStart;
  final bool awaitingAnswer;
  final bool processingAnswer;
  final String? lastError;

  bool get canStartSession {
    if (pendingVoiceStart) return false;
    if (voiceState.status == SessionStatus.loggedOut ||
        voiceState.status == SessionStatus.error) {
      return true;
    }
    if (voiceState.status == SessionStatus.ready && !sessionActive) {
      return true;
    }
    return false;
  }

  bool get canCloseSession =>
      pendingVoiceStart || voiceState.status != SessionStatus.loggedOut;

  VoxiaQuestionnaireState copyWith({
    VoxiaSessionState? voiceState,
    List<VoxiaQuestionMessage>? messages,
    String? summary,
    bool? sessionActive,
    bool? sessionCompleted,
    bool? pendingVoiceStart,
    bool? awaitingAnswer,
    bool? processingAnswer,
    String? lastError,
  }) {
    return VoxiaQuestionnaireState(
      voiceState: voiceState ?? this.voiceState,
      messages: messages ?? this.messages,
      summary: summary ?? this.summary,
      sessionActive: sessionActive ?? this.sessionActive,
      sessionCompleted: sessionCompleted ?? this.sessionCompleted,
      pendingVoiceStart: pendingVoiceStart ?? this.pendingVoiceStart,
      awaitingAnswer: awaitingAnswer ?? this.awaitingAnswer,
      processingAnswer: processingAnswer ?? this.processingAnswer,
      lastError: lastError,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VoxiaQuestionnaireState &&
        other.voiceState == voiceState &&
        listEquals(other.messages, messages) &&
        other.summary == summary &&
        other.sessionActive == sessionActive &&
        other.sessionCompleted == sessionCompleted &&
        other.pendingVoiceStart == pendingVoiceStart &&
        other.awaitingAnswer == awaitingAnswer &&
        other.processingAnswer == processingAnswer &&
        other.lastError == lastError;
  }

  @override
  int get hashCode => Object.hash(
    voiceState,
    Object.hashAll(messages),
    summary,
    sessionActive,
    sessionCompleted,
    pendingVoiceStart,
    awaitingAnswer,
    processingAnswer,
    lastError,
  );
}

class VoxiaQuestionnaireManager extends ChangeNotifier {
  VoxiaQuestionnaireManager({
    VoxiaController? voiceController,
    List<QuestionnaireSection>? questionnaire,
    String? questionnaireAssetPath,
  }) : _voiceController = voiceController ?? VoxiaController.defaultInstance(),
       _ownsVoiceController = voiceController == null,
       _questionnaireAssetPath =
           questionnaireAssetPath ?? defaultQuestionnaireAssetPath {
    _state = VoxiaQuestionnaireState.initial(_voiceController.state);
    _voiceController.addListener(_handleVoiceStateUpdate);
    if (questionnaire != null) {
      _questionnaireLoadFuture = _initializeWithSections(questionnaire);
    } else {
      _questionnaireLoadFuture = _loadQuestionnaireFromAsset(
        _questionnaireAssetPath,
      );
    }
  }
  final VoxiaController _voiceController;
  final bool _ownsVoiceController;
  final String _questionnaireAssetPath;

  List<QuestionnaireSection>? _questionnaire;
  _QuestionnaireFlowController? _flowController;
  Future<void>? _questionnaireLoadFuture;

    static const String defaultQuestionnaireAssetPath =
      'assets/questionnaires/default_questionnaire.json';

  static final Map<String, Future<List<QuestionnaireSection>>>
  _questionnaireCache = <String, Future<List<QuestionnaireSection>>>{};

  final List<VoxiaQuestionMessage> _messages = <VoxiaQuestionMessage>[];
  VoxiaQuestionnaireState _state = VoxiaQuestionnaireState.initial(
    VoxiaSessionState.initial(),
  );

  bool _sessionActive = false;
  bool _sessionCompleted = false;
  bool _pendingVoiceStart = false;
  bool _awaitingAnswer = false;
  bool _processingAnswer = false;
  String _summary = '';
  String _lastProcessedTranscript = '';
  String? _lastError;

  VoxiaQuestionnaireState get state => _state;

  Future<void> startSession() async {
    if (state.pendingVoiceStart) return;
    final bool ready = await _ensureQuestionnaireLoaded();
    if (!ready) {
      _lastError = 'No se pudo cargar el cuestionario.';
      _emitState();
      return;
    }
    _sessionCompleted = false;
    _summary = '';
    _messages.clear();
    _flowController?.reset();
    _emitState();

    if (_voiceController.state.status == SessionStatus.ready) {
      _sessionActive = true;
      _emitState();
      await _startQuestionnaireConversation();
      return;
    }

    _pendingVoiceStart = true;
    _emitState();
    await _voiceController.login();
  }

  Future<void> closeSession() async {
    _pendingVoiceStart = false;
    _sessionActive = false;
    _sessionCompleted = false;
    _awaitingAnswer = false;
    _processingAnswer = false;
    _lastProcessedTranscript = '';
    _summary = '';
    _messages.clear();
    _emitState();
    await _voiceController.logout();
  }

  @override
  void dispose() {
    _voiceController.removeListener(_handleVoiceStateUpdate);
    if (_ownsVoiceController) {
      _voiceController.dispose();
    }
    super.dispose();
  }

  Future<void> _startQuestionnaireConversation() async {
    if (_flowController == null) {
      _lastError = 'No se pudo inicializar el cuestionario.';
      _emitState();
      return;
    }
    _sessionCompleted = false;
    _awaitingAnswer = false;
    _processingAnswer = false;
    _lastProcessedTranscript = '';
    _messages
      ..clear()
      ..add(
        const VoxiaQuestionMessage.assistant(
          'Hola, soy Voxia, tu asistente virtual de curaciones. Te voy a guiar paso a paso.',
        ),
      );
    _emitState();

    await _voiceController.speakText(
      'Hola, soy Voxia, tu asistente virtual de curaciones. Te voy a guiar paso a paso.',
    );
    if (!_sessionActive) {
      _processingAnswer = false;
      _emitState();
      return;
    }

    await _askCurrentQuestion();
  }

  Future<void> _askCurrentQuestion() async {
    final _QuestionnaireFlowController? flow = _flowController;
    if (flow == null) {
      _lastError = 'No hay un cuestionario disponible.';
      _emitState();
      return;
    }
    final String? prompt = flow.currentPrompt;
    if (prompt == null) {
      await _finishQuestionnaire();
      return;
    }
    await _askSpecificQuestion(prompt);
  }

  Future<void> _askSpecificQuestion(String prompt) async {
    _messages.add(VoxiaQuestionMessage.assistant(prompt));
    _emitState();

    _voiceController.clearRecognizedText();
    await _voiceController.speakText(prompt);
    if (!_sessionActive) {
      _awaitingAnswer = false;
      _emitState();
      return;
    }

    _voiceController.clearRecognizedText();
    await _voiceController.startListening();
    _awaitingAnswer = true;
    _processingAnswer = false;
    _lastProcessedTranscript = '';
    _emitState();
  }

  Future<void> _handleVoiceAnswer(String transcript) async {
    _awaitingAnswer = false;
    _lastProcessedTranscript = transcript;
    _emitState();

    if (_voiceController.state.isListening) {
      await _voiceController.stopListening();
    }
    _voiceController.clearRecognizedText();

    final _QuestionnaireFlowController? flow = _flowController;
    if (flow == null) {
      _lastError = 'No hay un cuestionario listo para validar.';
      _emitState();
      _processingAnswer = false;
      return;
    }
    final _ValidationResult validation = flow.validateCurrentAnswer(transcript);
    if (!validation.isValid) {
      _messages
        ..add(VoxiaQuestionMessage.patient(transcript))
        ..add(VoxiaQuestionMessage.assistant(validation.errorMessage!));
      _emitState();

      await _voiceController.speakText(validation.errorMessage!);
      if (!_sessionActive) {
        _processingAnswer = false;
        _emitState();
        return;
      }

      await _askCurrentQuestion();
      _processingAnswer = false;
      _emitState();
      return;
    }

    final String normalized = validation.normalizedValue ?? transcript;
    final String echo = validation.echoResponse ?? normalized;
    _messages.add(VoxiaQuestionMessage.patient(echo));
    _emitState();

    flow.recordAnswer(normalized);
    final String? nextPrompt = flow.advanceAndGetPrompt();
    if (nextPrompt == null) {
      await _finishQuestionnaire();
    } else {
      await _askSpecificQuestion(nextPrompt);
    }
    _processingAnswer = false;
    _emitState();
  }

  Future<void> _finishQuestionnaire() async {
    final _QuestionnaireFlowController? flow = _flowController;
    if (flow == null) {
      _lastError = 'No se pudo finalizar el cuestionario cargado.';
      _emitState();
      return;
    }
    if (_voiceController.state.isListening) {
      await _voiceController.stopListening();
    }
    _voiceController.clearRecognizedText();

    _summary = flow.buildSummary();
    _sessionCompleted = true;
    _sessionActive = false;
    _messages.add(
      const VoxiaQuestionMessage.assistant(
        'Listo, ya tengo todos los datos necesarios. Gracias.',
      ),
    );
    _emitState();

    await _voiceController.speakText(
      'Listo, ya tengo todos los datos necesarios. Gracias.',
    );
  }

  Future<bool> _ensureQuestionnaireLoaded() async {
    if (_flowController != null) {
      return true;
    }
    _questionnaireLoadFuture ??= _loadQuestionnaireFromAsset(
      _questionnaireAssetPath,
    );
    try {
      await _questionnaireLoadFuture;
    } catch (e) {
      _questionnaireLoadFuture = null;
      _lastError = 'No se pudo cargar el cuestionario: $e';
      _emitState();
      return false;
    }
    if (_flowController == null) {
      _lastError ??= 'No se pudo cargar el cuestionario.';
      _emitState();
      return false;
    }
    return true;
  }

  Future<void> _initializeWithSections(List<QuestionnaireSection> sections) {
    _questionnaire = List<QuestionnaireSection>.unmodifiable(sections);
    _flowController = _QuestionnaireFlowController(_questionnaire!);
    return Future<void>.value();
  }

  Future<void> _loadQuestionnaireFromAsset(String assetPath) async {
    try {
      final Future<List<QuestionnaireSection>> loader = _questionnaireCache
          .putIfAbsent(assetPath, () async {
            final String raw = await rootBundle.loadString(assetPath);
            final List<dynamic> data = jsonDecode(raw) as List<dynamic>;
            return data
                .map(
                  (dynamic item) => QuestionnaireSection.fromJson(
                    item as Map<String, dynamic>,
                  ),
                )
                .toList();
          });
      final List<QuestionnaireSection> sections = await loader;
      await _initializeWithSections(sections);
    } catch (e) {
      _questionnaireCache.remove(assetPath);
      _lastError = 'No se pudo cargar el cuestionario: $e';
      _emitState();
      rethrow;
    }
  }

  void _handleVoiceStateUpdate() {
    final VoxiaSessionState previousVoiceState = _state.voiceState;
    final VoxiaSessionState currentVoiceState = _voiceController.state;

    if (_pendingVoiceStart && currentVoiceState.status == SessionStatus.ready) {
      _pendingVoiceStart = false;
      _sessionActive = true;
      _emitState();
      unawaited(_startQuestionnaireConversation());
      return;
    }

    if (_sessionActive &&
        _awaitingAnswer &&
        !_processingAnswer &&
        !currentVoiceState.isListening &&
        !currentVoiceState.silenceStopPending &&
        currentVoiceState.hasSpoken) {
      final String transcript = currentVoiceState.recognizedText.trim();
      if (transcript.isNotEmpty && transcript != _lastProcessedTranscript) {
        _processingAnswer = true;
        _emitState();
        unawaited(_handleVoiceAnswer(transcript));
        return;
      }
    }

    if (currentVoiceState.lastError != null &&
        currentVoiceState.lastError!.isNotEmpty &&
        currentVoiceState.lastError != previousVoiceState.lastError) {
      _messages.add(
        VoxiaQuestionMessage.assistant(
          'Hubo un inconveniente: ${currentVoiceState.lastError}. Intentemos de nuevo.',
        ),
      );
    }

    _emitState();
  }

  void _emitState() {
    final VoxiaQuestionnaireState newState = VoxiaQuestionnaireState(
      voiceState: _voiceController.state,
      messages: List<VoxiaQuestionMessage>.unmodifiable(_messages),
      summary: _summary,
      sessionActive: _sessionActive,
      sessionCompleted: _sessionCompleted,
      pendingVoiceStart: _pendingVoiceStart,
      awaitingAnswer: _awaitingAnswer,
      processingAnswer: _processingAnswer,
      lastError: _lastError ?? _voiceController.state.lastError,
    );

    if (_state == newState) {
      return;
    }
    _state = newState;
    notifyListeners();
  }
}

class _QuestionnaireFlowController {
  _QuestionnaireFlowController(List<QuestionnaireSection> sections)
    : sections = List<QuestionnaireSection>.unmodifiable(sections);

  final List<QuestionnaireSection> sections;
  final Map<String, String> _answers = <String, String>{};

  int _sectionIndex = 0;
  int _questionIndex = 0;

  QuestionnaireQuestion? get _currentQuestion {
    if (_sectionIndex >= sections.length) return null;
    final List<QuestionnaireQuestion> questions =
        sections[_sectionIndex].questions;
    if (_questionIndex >= questions.length) return null;
    return questions[_questionIndex];
  }

  String? get currentPrompt => _currentQuestion?.prompt;

  _ValidationResult validateCurrentAnswer(String raw) {
    final QuestionnaireQuestion? question = _currentQuestion;
    if (question == null) {
      return const _ValidationResult.invalid('No hay una pregunta activa.');
    }
    switch (question.type) {
      case QuestionFieldType.text:
        final String normalizedAnswer = raw.trim();
        if (normalizedAnswer.length < 2) {
          return const _ValidationResult.invalid(
            'Necesito al menos dos caracteres.',
          );
        }
        return _ValidationResult.valid(normalizedValue: normalizedAnswer);
      case QuestionFieldType.longText:
        final String normalizedLongText = raw.trim();
        if (normalizedLongText.length < 5) {
          return const _ValidationResult.invalid(
            'Dame un poco mas de contexto.',
          );
        }
        return _ValidationResult.valid(normalizedValue: normalizedLongText);
      case QuestionFieldType.date:
        final DateTime? parsed = _parseDate(raw);
        if (parsed == null) {
          return const _ValidationResult.invalid(
            'Formato de fecha invalido. Usa dd/mm/aaaa o aaaa-mm-dd.',
          );
        }
        final String normalized = _formatDate(parsed);
        return _ValidationResult.valid(
          normalizedValue: normalized,
          echoResponse: normalized,
        );
      case QuestionFieldType.number:
        final double? parsed = _extractFirstNumber(raw);
        if (parsed == null) {
          return const _ValidationResult.invalid('Necesito un numero valido.');
        }
        final String formatted = _formatNumber(parsed, question.unit);
        return _ValidationResult.valid(
          normalizedValue: formatted,
          echoResponse: formatted,
        );
      case QuestionFieldType.selection:
        final String? normalized = _matchOption(raw, question.options);
        if (normalized == null) {
          return _ValidationResult.invalid(
            'Responde con una de estas opciones: ${question.options.join(', ')}.',
          );
        }
        return _ValidationResult.valid(
          normalizedValue: normalized,
          echoResponse: normalized,
        );
      case QuestionFieldType.boolean:
        final bool? boolValue = _parseBool(raw);
        if (boolValue == null) {
          return const _ValidationResult.invalid('Responde si o no.');
        }
        final String normalized = boolValue ? 'Si' : 'No';
        return _ValidationResult.valid(
          normalizedValue: normalized,
          echoResponse: normalized,
        );
      case QuestionFieldType.booleanText:
        final bool? boolValue = _parseBool(raw);
        if (boolValue == null) {
          return const _ValidationResult.invalid(
            'Indica si o no y agrega detalles si aplica.',
          );
        }
        if (boolValue) {
          final String detail =
              raw
                  .replaceFirst(
                    RegExp(
                      '^\s*(si|s\u00ed|yes|y)(?:[:,-]\s*)?',
                      caseSensitive: false,
                    ),
                    '',
                  )
                  .trim();
          final String normalized =
              detail.isEmpty ? 'Si, sin detalle' : 'Si, $detail';
          return _ValidationResult.valid(
            normalizedValue: normalized,
            echoResponse: normalized,
          );
        }
        return const _ValidationResult.valid(
          normalizedValue: 'No',
          echoResponse: 'No',
        );
      case QuestionFieldType.range:
        final double? parsed = _extractFirstNumber(raw);
        if (parsed == null) {
          return const _ValidationResult.invalid(
            'Necesito un numero para la escala.',
          );
        }
        final num min = question.min ?? double.negativeInfinity;
        final num max = question.max ?? double.infinity;
        if (parsed < min || parsed > max) {
          return _ValidationResult.invalid(
            'Debe estar entre ${question.min} y ${question.max}.',
          );
        }
        final String normalized = parsed.toStringAsFixed(1);
        return _ValidationResult.valid(
          normalizedValue: normalized,
          echoResponse: normalized,
        );
    }
  }

  void recordAnswer(String value) {
    final QuestionnaireQuestion? question = _currentQuestion;
    if (question == null) return;
    final QuestionnaireSection section = sections[_sectionIndex];
    _answers[_buildKey(section.id, question.id)] = value;
  }

  String? advanceAndGetPrompt() {
    if (_sectionIndex >= sections.length) return null;
    _questionIndex++;
    if (_questionIndex >= sections[_sectionIndex].questions.length) {
      _sectionIndex++;
      _questionIndex = 0;
    }
    if (_sectionIndex >= sections.length) {
      return null;
    }
    return _currentQuestion?.prompt;
  }

  String buildSummary() {
    final StringBuffer buffer = StringBuffer();
    for (final QuestionnaireSection section in sections) {
      buffer.writeln(section.displayName.toUpperCase());
      for (final QuestionnaireQuestion question in section.questions) {
        final String key = _buildKey(section.id, question.id);
        final String answer = _answers[key] ?? 'Sin respuesta';
        buffer.writeln('- ${question.label}: $answer');
      }
      buffer.writeln();
    }
    return buffer.toString().trim();
  }

  void reset() {
    _answers.clear();
    _sectionIndex = 0;
    _questionIndex = 0;
  }

  static String _buildKey(String sectionId, String questionId) =>
      '$sectionId.$questionId';
}

class _ValidationResult {
  const _ValidationResult.valid({
    required this.normalizedValue,
    this.echoResponse,
  }) : isValid = true,
       errorMessage = null;

  const _ValidationResult.invalid(this.errorMessage)
    : isValid = false,
      normalizedValue = null,
      echoResponse = null;

  final bool isValid;
  final String? errorMessage;
  final String? normalizedValue;
  final String? echoResponse;
}

DateTime? _parseDate(String raw) {
  final String normalized = raw.trim();
  try {
    final DateTime parsed = DateTime.parse(normalized);
    return DateTime(parsed.year, parsed.month, parsed.day);
  } catch (_) {
    final RegExpMatch? match = RegExp(
      r'^(\d{2})[\/\-](\d{2})[\/\-](\d{4})$',
    ).firstMatch(normalized);
    if (match == null) return null;
    final int day = int.parse(match.group(1)!);
    final int month = int.parse(match.group(2)!);
    final int year = int.parse(match.group(3)!);
    return DateTime(year, month, day);
  }
}

String _formatDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year.toString().padLeft(4, '0')}';

String _formatNumber(double value, String? unit) {
  final String formatted =
      value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  return unit == null ? formatted : '$formatted $unit';
}

String? _matchOption(String raw, List<String> options) {
  if (options.isEmpty) return raw;
  final String normalizedInput = _normalizeForComparison(raw);
  if (normalizedInput.isEmpty) {
    return null;
  }

  String? bestMatch;
  int bestDistance = 1 << 30;

  for (final String option in options) {
    final String normalizedOption = _normalizeForComparison(option);
    if (normalizedOption == normalizedInput) {
      return option;
    }
    final int distance = _levenshteinDistance(
      normalizedInput,
      normalizedOption,
    );
    if (distance < bestDistance) {
      bestDistance = distance;
      bestMatch = option;
    }
  }

  final int threshold =
      normalizedInput.length <= 4 ? 1 : (normalizedInput.length / 3).ceil();
  if (bestMatch != null && bestDistance <= threshold) {
    return bestMatch;
  }

  final int? numeric = int.tryParse(normalizedInput);
  if (numeric != null && numeric > 0 && numeric <= options.length) {
    return options[numeric - 1];
  }
  return null;
}

double? _extractFirstNumber(String raw) {
  final RegExpMatch? match = RegExp(r'-?\d+(?:[.,]\d+)?').firstMatch(raw);
  if (match == null) {
    return null;
  }
  final String numeric = match.group(0)!.replaceAll(',', '.');
  return double.tryParse(numeric);
}

String _normalizeForComparison(String input) {
  return _stripAccents(input).toLowerCase().trim();
}

int _levenshteinDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  final List<int> prevRow = List<int>.generate(b.length + 1, (int i) => i);
  final List<int> curRow = List<int>.filled(b.length + 1, 0);

  for (int i = 0; i < a.length; i++) {
    curRow[0] = i + 1;
    for (int j = 0; j < b.length; j++) {
      final int insertCost = curRow[j] + 1;
      final int deleteCost = prevRow[j + 1] + 1;
      final int replaceCost = prevRow[j] + (a[i] == b[j] ? 0 : 1);

      int best = insertCost;
      if (deleteCost < best) {
        best = deleteCost;
      }
      if (replaceCost < best) {
        best = replaceCost;
      }
      curRow[j + 1] = best;
    }
    for (int j = 0; j <= b.length; j++) {
      prevRow[j] = curRow[j];
    }
  }

  return prevRow[b.length];
}

bool? _parseBool(String raw) {
  final String normalized = _normalizeForComparison(raw);
  if (normalized.startsWith('si') ||
      normalized == 's' ||
      normalized.startsWith('yes') ||
      normalized == 'y') {
    return true;
  }
  if (normalized.startsWith('no') || normalized == 'n') {
    return false;
  }
  return null;
}

String _stripAccents(String input) {
  const Map<String, String> replacements = <String, String>{
    '\u00e1': 'a',
    '\u00e0': 'a',
    '\u00e4': 'a',
    '\u00e2': 'a',
    '\u00e9': 'e',
    '\u00e8': 'e',
    '\u00eb': 'e',
    '\u00ea': 'e',
    '\u00ed': 'i',
    '\u00ec': 'i',
    '\u00ef': 'i',
    '\u00ee': 'i',
    '\u00f3': 'o',
    '\u00f2': 'o',
    '\u00f6': 'o',
    '\u00f4': 'o',
    '\u00fa': 'u',
    '\u00f9': 'u',
    '\u00fc': 'u',
    '\u00fb': 'u',
  };
  final StringBuffer buffer = StringBuffer();
  for (final int rune in input.runes) {
    final String char = String.fromCharCode(rune);
    buffer.write(replacements[char] ?? char);
  }
  return buffer.toString();
}

QuestionFieldType _questionFieldTypeFromString(String value) {
  switch (value.toLowerCase()) {
    case 'text':
      return QuestionFieldType.text;
    case 'longtext':
      return QuestionFieldType.longText;
    case 'date':
      return QuestionFieldType.date;
    case 'number':
      return QuestionFieldType.number;
    case 'selection':
      return QuestionFieldType.selection;
    case 'boolean':
      return QuestionFieldType.boolean;
    case 'booleantext':
      return QuestionFieldType.booleanText;
    case 'range':
      return QuestionFieldType.range;
  }
  throw ArgumentError('Tipo de pregunta no soportado: $value');
}
