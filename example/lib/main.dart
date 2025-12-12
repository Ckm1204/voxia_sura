import 'package:flutter/material.dart';
import 'package:sura_voxia/sura_voxia.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VoxiaDemoApp());
}

class VoxiaDemoApp extends StatelessWidget {
  const VoxiaDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TEST',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const VoxiaHomePage(title: 'TEST'),
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
  late final VoxiaController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VoxiaController.defaultInstance();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final VoxiaSessionState state = _controller.state;
        return Scaffold(
          appBar: AppBar(title: Text(widget.title)),
          body: SingleChildScrollView(
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
                      onPressed: state.status == SessionStatus.loggedOut ||
                              state.status == SessionStatus.error
                          ? _controller.login
                          : null,
                      child: Text(
                        state.status == SessionStatus.initializing
                            ? 'Iniciando...'
                            : 'Iniciar sesión',
                      ),
                    ),
                    ElevatedButton(
                      onPressed: state.canListen
                          ? () {
                              if (state.isListening) {
                                _controller.stopListening();
                              } else {
                                _controller.startListening();
                              }
                            }
                          : null,
                      child: Text(state.isListening ? 'Parar' : 'Escuchar'),
                    ),
                    ElevatedButton(
                      onPressed: state.status == SessionStatus.ready
                          ? () => _controller.playNotification()
                          : null,
                      child: const Text('Reproducir sonido'),
                    ),
                    ElevatedButton(
                      onPressed: state.status == SessionStatus.ready
                          ? () => _controller.speakText()
                          : null,
                      child: const Text('Escuchar texto'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _StatusRow(label: 'Estado sesión', value: state.status.name),
                _StatusRow(
                    label: 'Speech habilitado',
                    value: state.speechEnabled ? 'Sí' : 'No'),
                _StatusRow(
                    label: 'Escuchando',
                    value: state.isListening ? 'Sí' : 'No'),
                _StatusRow(
                    label: 'Auto-stop pendiente',
                    value: state.silenceStopPending ? 'Sí' : 'No'),
                _StatusRow(
                    label: 'Usuario habló',
                    value: state.hasSpoken ? 'Sí' : 'No'),
                _StatusRow(
                    label: 'Locale',
                    value: state.localeId.isEmpty ? 'unknown' : state.localeId),
                _StatusRow(label: 'Reconocido', value: state.recognizedText),
                if (state.lastError != null && state.lastError!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Error: ${state.lastError}',
                      style: const TextStyle(color: Colors.red)),
                ],
                const Divider(height: 32),
                const Text('Log'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  height: 180,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black26),
                  ),
                  child: SingleChildScrollView(
                    child: Text(state.logAsText.isEmpty
                        ? 'Sin eventos todavía'
                        : state.logAsText),
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
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
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
