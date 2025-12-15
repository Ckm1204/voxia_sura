import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sura_voxia/sura_voxia.dart';

/// Represents a full questionnaire broken into sections.
class QuestionnaireSection {
  const QuestionnaireSection({
    required this.id,
    required this.displayName,
    required this.questions,
  });

  final String id;
  final String displayName;
  final List<QuestionnaireQuestion> questions;
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

  final String id;
  final String label;
  final String prompt;
  final QuestionFieldType type;
  final List<String> options;
  final String? unit;
  final num? min;
  final num? max;
}

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

class NurseQuestionnaireScreen extends StatefulWidget {
  const NurseQuestionnaireScreen({super.key});

  @override
  State<NurseQuestionnaireScreen> createState() => _NurseQuestionnaireScreenState();
}

class _NurseQuestionnaireScreenState extends State<NurseQuestionnaireScreen> {
  final _flowController = _QuestionnaireFlowController(_questionnaireDefinition);
  final ScrollController _scrollController = ScrollController();
  final List<_ChatMessage> _messages = <_ChatMessage>[];

  late final VoxiaController _voiceController;
  VoxiaSessionState _voiceState = VoxiaSessionState.initial();

  bool _sessionActive = false;
  bool _sessionCompleted = false;
  bool _pendingVoiceStart = false;
  bool _awaitingAnswer = false;
  bool _processingAnswer = false;
  String _summary = '';
  String _lastProcessedTranscript = '';

  @override
  void initState() {
    super.initState();
    _voiceController = VoxiaController.defaultInstance();
    _voiceState = _voiceController.state;
    _voiceController.addListener(_handleVoiceStateUpdate);
  }

  @override
  void dispose() {
    _voiceController.removeListener(_handleVoiceStateUpdate);
    _voiceController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool get _canStartSession {
    if (_pendingVoiceStart) return false;
    if (_voiceState.status == SessionStatus.loggedOut || _voiceState.status == SessionStatus.error) {
      return true;
    }
    if (_voiceState.status == SessionStatus.ready && !_sessionActive) {
      return true;
    }
    return false;
  }

  bool get _canCloseSession => _pendingVoiceStart || _voiceState.status != SessionStatus.loggedOut;

  Future<void> _handleStartSession() async {
    if (!_canStartSession) return;
    _sessionCompleted = false;
    _summary = '';
    _flowController.reset();
    _messages.clear();

    if (_voiceState.status == SessionStatus.ready) {
      _sessionActive = true;
      await _startQuestionnaireConversation();
      setState(() {});
      return;
    }

    setState(() => _pendingVoiceStart = true);
    await _voiceController.login();
  }

  Future<void> _handleLogout() async {
    _pendingVoiceStart = false;
    _sessionActive = false;
    _sessionCompleted = false;
    _awaitingAnswer = false;
    _processingAnswer = false;
    _lastProcessedTranscript = '';
    await _voiceController.logout();
    if (!mounted) return;
    setState(() {});
  }

  void _handleVoiceStateUpdate() {
    if (!mounted) return;
    final previousState = _voiceState;
    _voiceState = _voiceController.state;

    if (_pendingVoiceStart && _voiceState.status == SessionStatus.ready) {
      _pendingVoiceStart = false;
      _sessionActive = true;
      unawaited(_startQuestionnaireConversation());
    }

    if (_sessionActive &&
        _awaitingAnswer &&
        !_processingAnswer &&
        !_voiceState.isListening &&
        !_voiceState.silenceStopPending &&
        _voiceState.hasSpoken) {
      final transcript = _voiceState.recognizedText.trim();
      if (transcript.isNotEmpty && transcript != _lastProcessedTranscript) {
        _processingAnswer = true;
        unawaited(_handleVoiceAnswer(transcript));
      }
    }

    if (_voiceState.lastError != null &&
        _voiceState.lastError!.isNotEmpty &&
        _voiceState.lastError != previousState.lastError) {
      setState(() {
        _messages.add(_ChatMessage.nurse('Hubo un inconveniente: ${_voiceState.lastError}. Intentemos de nuevo.'));
      });
      _scrollToBottom();
      return;
    }

    setState(() {});
  }

  Future<void> _startQuestionnaireConversation() async {
    _sessionCompleted = false;
    _awaitingAnswer = false;
    _processingAnswer = false;
    _lastProcessedTranscript = '';

    if (!mounted) return;
    setState(() {
      _messages
        ..clear()
        ..add(const _ChatMessage.nurse(
            'Hola, soy Voxia, tu asistente virtual de curaciones. Te voy a guiar paso a paso.'));
    });
    _scrollToBottom();

    await _voiceController.speakText(
      'Hola, soy Voxia, tu asistente virtual de curaciones. Te voy a guiar paso a paso.',
    );
    if (!mounted || !_sessionActive) {
      _processingAnswer = false;
      return;
    }

    await _askCurrentQuestion();
  }

  Future<void> _askCurrentQuestion() async {
    final prompt = _flowController.currentPrompt;
    if (prompt == null) {
      await _finishQuestionnaire();
      return;
    }
    await _askSpecificQuestion(prompt);
  }

  Future<void> _askSpecificQuestion(String prompt) async {
    if (!mounted) return;
    setState(() => _messages.add(_ChatMessage.nurse(prompt)));
    _scrollToBottom();

    _voiceController.clearRecognizedText();
    await _voiceController.speakText(prompt);
    if (!mounted || !_sessionActive) {
      _awaitingAnswer = false;
      return;
    }

    _voiceController.clearRecognizedText();
    await _voiceController.startListening();
    _awaitingAnswer = true;
    _processingAnswer = false;
    _lastProcessedTranscript = '';
  }

  Future<void> _handleVoiceAnswer(String transcript) async {
    if (!mounted) {
      _processingAnswer = false;
      return;
    }

    _awaitingAnswer = false;
    _lastProcessedTranscript = transcript;

    if (_voiceState.isListening) {
      await _voiceController.stopListening();
    }
    _voiceController.clearRecognizedText();

    final validation = _flowController.validateCurrentAnswer(transcript);

    if (!mounted) {
      _processingAnswer = false;
      return;
    }

    if (!validation.isValid) {
      setState(() {
        _messages.add(_ChatMessage.patient(transcript));
        _messages.add(_ChatMessage.nurse(validation.errorMessage!));
      });
      _scrollToBottom();

      await _voiceController.speakText(validation.errorMessage!);
      if (!_sessionActive) {
        _processingAnswer = false;
        return;
      }

      await _askCurrentQuestion();
      _processingAnswer = false;
      return;
    }

    final normalized = validation.normalizedValue ?? transcript;
    final echo = validation.echoResponse ?? normalized;
    setState(() => _messages.add(_ChatMessage.patient(echo)));
    _scrollToBottom();

    _flowController.recordAnswer(normalized);
    final nextPrompt = _flowController.advanceAndGetPrompt();
    if (nextPrompt == null) {
      await _finishQuestionnaire();
    } else {
      await _askSpecificQuestion(nextPrompt);
    }
    _processingAnswer = false;
  }

  Future<void> _finishQuestionnaire() async {
    if (_voiceState.isListening) {
      await _voiceController.stopListening();
    }
    _voiceController.clearRecognizedText();

    final summaryText = _flowController.buildSummary();
    if (!mounted) return;
    setState(() {
      _sessionCompleted = true;
      _sessionActive = false;
      _summary = summaryText;
      _messages.add(const _ChatMessage.nurse('Listo, ya tengo todos los datos necesarios. Gracias.'));
    });
    _scrollToBottom();

    await _voiceController.speakText('Listo, ya tengo todos los datos necesarios. Gracias.');
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Asistente de curaciones Voxia', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Pulsa iniciar sesion para que Voxia formule cada pregunta en voz y registre tus respuestas automaticamente.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: _canStartSession ? _handleStartSession : null,
                icon: const Icon(Icons.mic),
                label: Text(
                  _pendingVoiceStart
                      ? 'Iniciando...'
                      : _voiceState.status == SessionStatus.ready && !_sessionActive
                          ? 'Comenzar cuestionario'
                          : 'Iniciar sesion',
                ),
              ),
              OutlinedButton.icon(
                onPressed: _canCloseSession ? _handleLogout : null,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Cerrar sesion'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _StatusChip(label: 'Estado', value: _voiceState.status.name),
          const SizedBox(height: 4),
          _StatusChip(
            label: 'Speech',
            value: _voiceState.speechEnabled ? 'Habilitado' : 'No disponible',
          ),
          const SizedBox(height: 4),
          _StatusChip(label: 'Escuchando', value: _voiceState.isListening ? 'Si' : 'No'),
          if (_voiceState.lastError != null && _voiceState.lastError!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Error: ${_voiceState.lastError}', style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[index];
                  final isPatient = message.role == _ChatRole.patient;
                  final alignment = isPatient ? Alignment.centerRight : Alignment.centerLeft;
                  final background = isPatient
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.secondaryContainer;
                  final textColor = isPatient
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : Colors.black87;

                  return Align(
                    alignment: alignment,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: background,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(message.text, style: TextStyle(color: textColor)),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_summary.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Resumen listo para copiar', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  SelectableText(_summary, style: const TextStyle(fontFamily: 'monospace')),
                ],
              ),
            ),
        ],
      ),
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

class _ChatMessage {
  const _ChatMessage._(this.text, this.role);

  const _ChatMessage.nurse(String text) : this._(text, _ChatRole.nurse);
  const _ChatMessage.patient(String text) : this._(text, _ChatRole.patient);

  final String text;
  final _ChatRole role;
}

enum _ChatRole { nurse, patient }

class _ValidationResult {
  const _ValidationResult.valid({required this.normalizedValue, this.echoResponse})
      : isValid = true,
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

class _QuestionnaireFlowController {
  _QuestionnaireFlowController(this.sections);

  final List<QuestionnaireSection> sections;
  final Map<String, String> _answers = <String, String>{};

  int _sectionIndex = 0;
  int _questionIndex = 0;

  QuestionnaireQuestion? get _currentQuestion {
    if (_sectionIndex >= sections.length) return null;
    final questions = sections[_sectionIndex].questions;
    if (_questionIndex >= questions.length) return null;
    return questions[_questionIndex];
  }

  String? get currentPrompt => _currentQuestion?.prompt;

  _ValidationResult validateCurrentAnswer(String raw) {
    final question = _currentQuestion;
    if (question == null) {
      return const _ValidationResult.invalid('No hay una pregunta activa.');
    }
    switch (question.type) {
      case QuestionFieldType.text:
        if (raw.length < 2) {
          return const _ValidationResult.invalid('Necesito al menos dos caracteres.');
        }
        return _ValidationResult.valid(normalizedValue: raw);
      case QuestionFieldType.longText:
        if (raw.length < 5) {
          return const _ValidationResult.invalid('Dame un poco mas de contexto.');
        }
        return _ValidationResult.valid(normalizedValue: raw);
      case QuestionFieldType.date:
        final parsed = _parseDate(raw);
        if (parsed == null) {
          return const _ValidationResult.invalid('Formato de fecha invalido. Usa dd/mm/aaaa o aaaa-mm-dd.');
        }
        final normalized = _formatDate(parsed);
        return _ValidationResult.valid(normalizedValue: normalized, echoResponse: normalized);
      case QuestionFieldType.number:
        final parsed = double.tryParse(raw.replaceAll(',', '.'));
        if (parsed == null) {
          return const _ValidationResult.invalid('Necesito un numero valido.');
        }
        final formatted = _formatNumber(parsed, question.unit);
        return _ValidationResult.valid(normalizedValue: formatted, echoResponse: formatted);
      case QuestionFieldType.selection:
        final normalized = _matchOption(raw, question.options);
        if (normalized == null) {
          return _ValidationResult.invalid('Responde con una de estas opciones: ${question.options.join(', ')}.');
        }
        return _ValidationResult.valid(normalizedValue: normalized, echoResponse: normalized);
      case QuestionFieldType.boolean:
        final boolValue = _parseBool(raw);
        if (boolValue == null) {
          return const _ValidationResult.invalid('Responde si o no.');
        }
        final normalized = boolValue ? 'Si' : 'No';
        return _ValidationResult.valid(normalizedValue: normalized, echoResponse: normalized);
      case QuestionFieldType.booleanText:
        final boolValue = _parseBool(raw);
        if (boolValue == null) {
          return const _ValidationResult.invalid('Indica si o no y agrega detalles si aplica.');
        }
        if (boolValue) {
          final detail = raw.replaceFirst(
            RegExp('^\\s*(si|s\u00ed|yes|y)(?:[:,-]\\s*)?', caseSensitive: false),
            '',
          ).trim();
          final normalized = detail.isEmpty ? 'Si, sin detalle' : 'Si, $detail';
          return _ValidationResult.valid(normalizedValue: normalized, echoResponse: normalized);
        }
        return const _ValidationResult.valid(normalizedValue: 'No', echoResponse: 'No');
      case QuestionFieldType.range:
        final parsed = double.tryParse(raw.replaceAll(',', '.'));
        if (parsed == null) {
          return const _ValidationResult.invalid('Necesito un numero para la escala.');
        }
        final min = question.min ?? double.negativeInfinity;
        final max = question.max ?? double.infinity;
        if (parsed < min || parsed > max) {
          return _ValidationResult.invalid('Debe estar entre ${question.min} y ${question.max}.');
        }
        final normalized = parsed.toStringAsFixed(1);
        return _ValidationResult.valid(normalizedValue: normalized, echoResponse: normalized);
    }
  }

  void recordAnswer(String value) {
    final question = _currentQuestion;
    if (question == null) return;
    final section = sections[_sectionIndex];
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
    final buffer = StringBuffer();
    for (final section in sections) {
      buffer.writeln(section.displayName.toUpperCase());
      for (final question in section.questions) {
        final key = _buildKey(section.id, question.id);
        final answer = _answers[key] ?? 'Sin respuesta';
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

  static String _buildKey(String sectionId, String questionId) => '$sectionId.$questionId';
}

DateTime? _parseDate(String raw) {
  final normalized = raw.trim();
  try {
    final parsed = DateTime.parse(normalized);
    return DateTime(parsed.year, parsed.month, parsed.day);
  } catch (_) {
    final match = RegExp(r'^(\d{2})[\/-](\d{2})[\/-](\d{4})$').firstMatch(normalized);
    if (match == null) return null;
    final day = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final year = int.parse(match.group(3)!);
    return DateTime(year, month, day);
  }
}

String _formatDate(DateTime date) => '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year.toString().padLeft(4, '0')}';

String _formatNumber(double value, String? unit) {
  final formatted = value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  return unit == null ? formatted : '$formatted $unit';
}

String? _matchOption(String raw, List<String> options) {
  if (options.isEmpty) return raw;
  final normalized = raw.trim().toLowerCase();
  for (final option in options) {
    if (option.toLowerCase() == normalized) {
      return option;
    }
  }
  final numeric = int.tryParse(normalized);
  if (numeric != null && numeric > 0 && numeric <= options.length) {
    return options[numeric - 1];
  }
  return null;
}

bool? _parseBool(String raw) {
  final normalized = _stripAccents(raw.trim().toLowerCase());
  if (normalized.startsWith('si') || normalized == 's' || normalized.startsWith('yes') || normalized == 'y') {
    return true;
  }
  if (normalized.startsWith('no') || normalized == 'n') {
    return false;
  }
  return null;
}

String _stripAccents(String input) {
  const replacements = <String, String>{
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
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(replacements[char] ?? char);
  }
  return buffer.toString();
}

final List<QuestionnaireSection> _questionnaireDefinition = <QuestionnaireSection>[
  QuestionnaireSection(
    id: 'identificacion',
    displayName: 'Datos de identificacion',
    questions: <QuestionnaireQuestion>[
      QuestionnaireQuestion(
        id: 'nombre',
        label: 'Nombre completo',
        prompt: 'Para registrar la atencion, cual es tu nombre completo?',
        type: QuestionFieldType.text,
      ),
      QuestionnaireQuestion(
        id: 'fecha_nacimiento',
        label: 'Fecha de nacimiento',
        prompt: 'Ahora dime tu fecha de nacimiento.',
        type: QuestionFieldType.date,
      ),
      QuestionnaireQuestion(
        id: 'genero',
        label: 'Genero',
        prompt: 'Con que genero te identificas? Opciones: Femenino, Masculino, Otro o Prefiero no decir.',
        type: QuestionFieldType.selection,
        options: <String>['Femenino', 'Masculino', 'Otro', 'Prefiero no decir'],
      ),
      QuestionnaireQuestion(
        id: 'telefono_contacto',
        label: 'Telefono de contacto',
        prompt: 'Cual es el telefono de contacto por si necesitamos avisos?',
        type: QuestionFieldType.text,
      ),
      QuestionnaireQuestion(
        id: 'motivo_consulta',
        label: 'Motivo principal',
        prompt: 'Explicame brevemente el motivo principal de la consulta o curacion.',
        type: QuestionFieldType.longText,
      ),
    ],
  ),
  QuestionnaireSection(
    id: 'signos',
    displayName: 'Signos vitales',
    questions: <QuestionnaireQuestion>[
      QuestionnaireQuestion(
        id: 'temperatura',
        label: 'Temperatura corporal',
        prompt: 'Temperatura corporal actual en grados centigrados?',
        type: QuestionFieldType.number,
        unit: 'C',
      ),
      QuestionnaireQuestion(
        id: 'presion_sistolica',
        label: 'Presion arterial sistolica',
        prompt: 'Presion sistolica en mmHg?',
        type: QuestionFieldType.number,
        unit: 'mmHg',
      ),
      QuestionnaireQuestion(
        id: 'presion_diastolica',
        label: 'Presion arterial diastolica',
        prompt: 'Presion diastolica en mmHg?',
        type: QuestionFieldType.number,
        unit: 'mmHg',
      ),
      QuestionnaireQuestion(
        id: 'frecuencia_cardiaca',
        label: 'Frecuencia cardiaca',
        prompt: 'Frecuencia cardiaca en latidos por minuto?',
        type: QuestionFieldType.number,
        unit: 'lpm',
      ),
      QuestionnaireQuestion(
        id: 'frecuencia_respiratoria',
        label: 'Frecuencia respiratoria',
        prompt: 'Frecuencia respiratoria en respiraciones por minuto?',
        type: QuestionFieldType.number,
        unit: 'rpm',
      ),
      QuestionnaireQuestion(
        id: 'saturacion_oxigeno',
        label: 'Saturacion de oxigeno',
        prompt: 'Saturacion de oxigeno en porcentaje?',
        type: QuestionFieldType.number,
        unit: '%',
      ),
      QuestionnaireQuestion(
        id: 'peso',
        label: 'Peso',
        prompt: 'Peso del paciente en kilogramos?',
        type: QuestionFieldType.number,
        unit: 'kg',
      ),
      QuestionnaireQuestion(
        id: 'altura',
        label: 'Altura',
        prompt: 'Altura en centimetros?',
        type: QuestionFieldType.number,
        unit: 'cm',
      ),
    ],
  ),
  QuestionnaireSection(
    id: 'antecedentes',
    displayName: 'Antecedentes medicos basicos',
    questions: <QuestionnaireQuestion>[
      QuestionnaireQuestion(
        id: 'alergias',
        label: 'Alergias conocidas',
        prompt: 'El paciente reporta alergias? si es asi menciona cuales.',
        type: QuestionFieldType.booleanText,
      ),
      QuestionnaireQuestion(
        id: 'medicamentos_actuales',
        label: 'Medicamentos actuales',
        prompt: 'Medicamentos actuales con dosis y frecuencia.',
        type: QuestionFieldType.longText,
      ),
      QuestionnaireQuestion(
        id: 'enfermedades_previas',
        label: 'Enfermedades o cirugias previas',
        prompt: 'Enfermedades cronicas o cirugias relevantes?',
        type: QuestionFieldType.longText,
      ),
      QuestionnaireQuestion(
        id: 'dolor_actual',
        label: 'Dolor actual',
        prompt: 'Tiene dolor en este momento? responde si o no.',
        type: QuestionFieldType.boolean,
      ),
      QuestionnaireQuestion(
        id: 'escala_dolor',
        label: 'Escala de dolor',
        prompt: 'Si hay dolor, dame la intensidad del 0 al 10.',
        type: QuestionFieldType.range,
        min: 0,
        max: 10,
      ),
    ],
  ),
];
