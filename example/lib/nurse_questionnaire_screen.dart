import 'package:flutter/material.dart';
import 'package:sura_voxia/sura_voxia.dart';

class NurseQuestionnaireScreen extends StatefulWidget {
  const NurseQuestionnaireScreen({super.key});

  @override
  State<NurseQuestionnaireScreen> createState() => _NurseQuestionnaireScreenState();
}

class _NurseQuestionnaireScreenState extends State<NurseQuestionnaireScreen> {
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
          appBar: AppBar(
            title: const Text('Asistente de curaciones Voxia'),
          ),
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
                          value: state.sessionActive
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
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: state.messages.isEmpty
                    ? const Center(child: Text('Aun no hay mensajes. Inicia la sesion para hablar con Voxia.'))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: state.messages.length,
                        itemBuilder: (BuildContext context, int index) {
                          final VoxiaQuestionMessage message = state.messages[index];
                          final bool isAssistant = message.role == VoxiaQuestionMessageRole.assistant;
                          final Color background = isAssistant
                              ? theme.colorScheme.primary.withOpacity(0.1)
                              : theme.colorScheme.secondaryContainer;

                          return Align(
                            alignment: isAssistant ? Alignment.centerLeft : Alignment.centerRight,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              constraints: const BoxConstraints(maxWidth: 320),
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
                    onPressed: state.canStartSession ? () => _manager.startSession() : null,
                    icon: const Icon(Icons.mic_none),
                    label: const Text('Iniciar Voxia'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: state.canCloseSession ? () => _manager.closeSession() : null,
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
