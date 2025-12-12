import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

void main() => runApp(TtsSstDemo());

class TtsSstDemo extends StatefulWidget {
  @override
  _TtsSstDemoState createState() => _TtsSstDemoState();
}

class _TtsSstDemoState extends State<TtsSstDemo> {
  late FlutterTts flutterTts;
  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  bool _isListening = false;
  String _recognizedText = '';

  double volume = 0.5;
  double pitch = 1.0;
  double rate = 0.5;

  @override
  void initState() {
    super.initState();
    initTts();
    _initSpeech();
  }

  void initTts() {
    flutterTts = FlutterTts();
    flutterTts.setStartHandler(() {
      // optional
    });
    flutterTts.setCompletionHandler(() {
      // optional
    });
    flutterTts.setErrorHandler((msg) {
      // optional
    });
  }

  @override
  void dispose() {
    flutterTts.stop();
    _speechToText.stop();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    final available = await _speechToText.initialize(
      onError: _onSpeechError,
      onStatus: _onSpeechStatus,
    );
    setState(() {
      _speechEnabled = available;
    });
  }

  void _onSpeechStatus(String status) {
    setState(() {
      _isListening = status == 'listening';
    });
    // When plugin reports done/notListening, speak the last recognized text
    if (status == 'done' || status == 'notListening') {
      if (_recognizedText.isNotEmpty) {
        _speak(_recognizedText);
      }
    }
  }

  void _onSpeechError(SpeechRecognitionError error) {
    // handle error if needed
    print('Speech error: ${error.errorMsg}');
  }

  Future<void> _speak(String text) async {
    await flutterTts.setVolume(volume);
    await flutterTts.setSpeechRate(rate);
    await flutterTts.setPitch(pitch);
    if (text.isNotEmpty) await flutterTts.speak(text);
  }

  Future<void> _startListening() async {
    if (!_speechEnabled) {
      await _initSpeech();
    }

    await _speechToText.listen(
      onResult: (result) {
        // update UI on all results
        setState(() {
            _recognizedText = (result.recognizedWords as String?) ?? '';
          });
        // note: we speak once the plugin reports 'done' via the onStatus handler
      },
      listenFor: Duration(seconds: 60),
      pauseFor: Duration(seconds: 5),
      partialResults: true,
      listenMode: ListenMode.dictation,
    );
  }

  Future<void> _stopListening() async {
    await _speechToText.stop();
  }

  void _toggleListening() {
    if (_isListening) {
      _stopListening();
    } else {
      _startListening();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('TTS + SST Demo')),
        body: Padding(
          padding: EdgeInsets.all(16.0),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: _toggleListening,
                    icon: Icon(Icons.mic),
                    label: Text(_isListening ? 'Parar' : 'Escuchar'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _speak(_recognizedText),
                    icon: Icon(Icons.volume_up),
                    label: Text('Escuchar Texto'),
                  ),
                ],
              ),
              SizedBox(height: 16.0),
              Text('Reconocido:'),
              SizedBox(height: 8.0),
              Expanded(
                child: SingleChildScrollView(
                  child: Text(_recognizedText, style: TextStyle(fontSize: 18)),
                ),
              ),
              SizedBox(height: 12.0),
              Row(children: [Text('Volumen'), Expanded(child: Slider(value: volume, min: 0.0, max: 1.0, onChanged: (v) => setState(() => volume = v)))]),
              Row(children: [Text('Pitch'), Expanded(child: Slider(value: pitch, min: 0.5, max: 2.0, onChanged: (v) => setState(() => pitch = v)))]),
              Row(children: [Text('Rate'), Expanded(child: Slider(value: rate, min: 0.0, max: 1.0, onChanged: (v) => setState(() => rate = v)))]),
            ],
          ),
        ),
      ),
    );
  }
}
