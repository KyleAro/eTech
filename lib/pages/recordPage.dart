import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../style/mainpage_style.dart';
import '../widgets/stateless/recordtitle.dart';
import '../widgets/stateful/audioplayer.dart';
import '../database/firebase_con.dart';
import '../database/firestore_con.dart';
import '../widgets/stateless/result_botsheet.dart';

class RecordPage extends StatefulWidget {
  @override
  _RecordPageState createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {
  final recorder = FlutterSoundRecorder();
  final TextEditingController titleController = TextEditingController();

  bool isRecorderReady = false;
  bool isRecording = false;
  bool isPredicting = false;

  String? pcmPath;

  @override
  void initState() {
    super.initState();
    _initRecorder();
  }

  @override
  void dispose() {
    recorder.closeRecorder();
    titleController.dispose();
    super.dispose();
  }

  Future<void> _initRecorder() async {
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) throw 'Microphone permission not granted';

    await recorder.openRecorder();
    if (!mounted) return;
    setState(() => isRecorderReady = true);
    recorder.setSubscriptionDuration(const Duration(milliseconds: 500));
  }

  Future<String> _generatePcmPath() async {
    final dir = await getExternalStorageDirectory();
    int count = 1;
    String path = '';
    while (true) {
      path = '${dir!.path}/Recording_$count.pcm';
      if (!await File(path).exists()) break;
      count++;
    }
    return path;
  }

  Future<void> startRecording() async {
    if (!isRecorderReady || isRecording) return;

    pcmPath = await _generatePcmPath();
    titleController.text = pcmPath!.split('/').last.split('.').first;

    await recorder.startRecorder(
      toFile: pcmPath,
      codec: Codec.pcm16, // pure PCM
    );

    setState(() => isRecording = true);
    _showRecordingBottomSheet();
  }

  Future<void> stopRecording({bool discard = false}) async {
    if (!isRecorderReady || !isRecording) return;

    await recorder.stopRecorder();
    setState(() => isRecording = false);

    if (discard) {
      if (pcmPath != null && await File(pcmPath!).exists()) await File(pcmPath!).delete();
      pcmPath = null;
      titleController.clear();
    }
  }

  Future<Map<String, dynamic>> _sendToMLServer(String pcmFile) async {
    final uri = Uri.parse("https://etech-rgsx.onrender.com/predict");
    final request = http.MultipartRequest("POST", uri);

    // Send PCM directly
    request.files.add(await http.MultipartFile.fromPath(
      "file",
      pcmFile,
      contentType: MediaType('audio', 'pcm'),
    ));

    final response = await request.send();
    final respStr = await response.stream.bytesToString();

    if (response.statusCode != 200) throw Exception("Server error: ${response.statusCode}");

    final decoded = jsonDecode(respStr);
    decoded["wav_base64"] ??= "";
    decoded["prediction"] ??= "Unknown";
    decoded["confidence"] ??= 0.0;

    return decoded;
  }

  void _showRecordingBottomSheet() {
    bool showExtraButtons = false;
    final audioPlayerService = AudioPlayerService();

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => WillPopScope(
        onWillPop: () async => !isPredicting,
        child: StatefulBuilder(builder: (context, setModalState) {
          return FractionallySizedBox(
            heightFactor: 0.6,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  RecordTitleField(showTitleField: showExtraButtons, titleController: titleController),
                  const SizedBox(height: 20),

                  StreamBuilder<RecordingDisposition>(
                    stream: recorder.onProgress,
                    builder: (context, snapshot) {
                      final d = snapshot.hasData ? snapshot.data!.duration : Duration.zero;
                      final m = d.inMinutes.toString().padLeft(2, '0');
                      final s = (d.inSeconds % 60).toString().padLeft(2, '0');
                      return Text('$m:$s', style: const TextStyle(fontSize: 50, color: Colors.white, fontWeight: FontWeight.bold));
                    },
                  ),

                  const SizedBox(height: 20),

                  if (!showExtraButtons)
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(shape: const CircleBorder(), padding: const EdgeInsets.all(20), backgroundColor: Colors.orangeAccent),
                      onPressed: () async {
                        await stopRecording();
                        setModalState(() => showExtraButtons = true);
                      },
                      child: const Icon(Icons.stop, size: 30, color: Colors.white),
                    ),

                  const SizedBox(height: 20),

                  if (showExtraButtons && pcmPath != null)
                    AudioPlayerControls(audioPlayer: audioPlayerService, filePath: pcmPath!),

                  const SizedBox(height: 20),

                  if (showExtraButtons)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: isPredicting ? Colors.grey : Colors.blueAccent, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15)),
                          onPressed: (pcmPath == null || isPredicting)
                              ? null
                              : () async {
                                  setState(() => isPredicting = true);

                                  try {
                                    final result = await _sendToMLServer(pcmPath!);

                                    Uint8List? cleanedPcm;
                                    if (result['wav_base64'] != "") cleanedPcm = base64Decode(result['wav_base64']);

                                    ResultBottomSheet.show(
                                      context,
                                      prediction: result['prediction'],
                                      confidence: result['confidence'],
                                      rawBytes: cleanedPcm,
                                      baseName: titleController.text.trim(),
                                    );

                                  } catch (_) {
                                    ResultBottomSheet.show(
                                      context,
                                      prediction: "Prediction failed",
                                      confidence: 0,
                                      isError: true,
                                    );
                                  }

                                  setState(() => isPredicting = false);
                                },
                          child: isPredicting
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
                                    SizedBox(width: 10),
                                    Text('Predicting...', style: TextStyle(color: Colors.white)),
                                  ],
                                )
                              : const Text('Predict', style: TextStyle(color: Colors.white)),
                        ),

                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color.fromARGB(255, 223, 111, 103), padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15)),
                          onPressed: () async {
                            await stopRecording(discard: true);
                            Navigator.pop(context);
                          },
                          child: const Text('Discard', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          body: Center(
            child: GestureDetector(
              onTap: () async {
                if (!isRecording) await startRecording();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 200,
                width: 200,
                child: NeuBox(
                  isPressed: isRecording,
                  child: Icon(isRecording ? Icons.stop : Icons.mic, size: 100, color: Colors.black),
                ),
              ),
            ),
          ),
        ),

        if (isPredicting)
          Positioned.fill(
            child: Container(
              color: Colors.black54,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 20),
                  Text("Predicting...", style: TextStyle(color: Colors.white, fontSize: 18)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
