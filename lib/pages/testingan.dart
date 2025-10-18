import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Sound Demo',
      home: SoundDemo(),
    );
  }
}

class SoundDemo extends StatefulWidget {
  @override
  _SoundDemoState createState() => _SoundDemoState();
}

class _SoundDemoState extends State<SoundDemo> {
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _player = FlutterSoundPlayer();

  bool _isRecorderInitialized = false;
  bool _isPlayerInitialized = false;

  bool _isRecording = false;
  bool _isPlaying = false;

  String? _filePath;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await Permission.microphone.request();

    await _recorder.openRecorder();
    _isRecorderInitialized = true;

    await _player.openPlayer();
    _isPlayerInitialized = true;

    setState(() {});
  }

  @override
  void dispose() {
    _recorder.closeRecorder();
    _player.closePlayer();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (!_isRecorderInitialized) return;

    _filePath = 'flutter_sound_example.aac';
    await _recorder.startRecorder(
      toFile: _filePath,
      codec: Codec.aacADTS,
    );

    setState(() {
      _isRecording = true;
    });
  }

  Future<void> _stopRecording() async {
    if (!_isRecorderInitialized) return;

    await _recorder.stopRecorder();

    setState(() {
      _isRecording = false;
    });
  }

  void _toggleRecording() {
    if (_isRecording) {
      _stopRecording();
    } else {
      _startRecording();
    }
  }

  Future<void> _startPlaying() async {
    if (!_isPlayerInitialized || _filePath == null) return;

    await _player.startPlayer(
      fromURI: _filePath,
      codec: Codec.aacADTS,
      whenFinished: () {
        setState(() {
          _isPlaying = false;
        });
      },
    );

    setState(() {
      _isPlaying = true;
    });
  }

  Future<void> _stopPlaying() async {
    if (!_isPlayerInitialized) return;

    await _player.stopPlayer();

    setState(() {
      _isPlaying = false;
    });
  }

  void _togglePlay() {
    if (_isPlaying) {
      _stopPlaying();
    } else {
      _startPlaying();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Flutter Sound Demo')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: _isRecorderInitialized ? _toggleRecording : null,
              child: Text(_isRecording ? 'Stop Recording' : 'Start Recording'),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: (_filePath != null && _isPlayerInitialized) ? _togglePlay : null,
              child: Text(_isPlaying ? 'Stop Playing' : 'Play Recording'),
            ),
          ],
        ),
      ),
    );
  }
}
