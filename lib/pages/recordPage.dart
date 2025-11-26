import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:etech/pages/MainPage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../style/mainpage_style.dart';
import '../widgets/stateless/recordtitle.dart';
import '../widgets/stateful/audioplayer.dart';
import '../widgets/stateful/audio_cleaner.dart'; 
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
  bool isProcessingAudio = false;
  bool isPredicting = false;

  String? rawAacPath;
  String? cleanedAacPath;
  String? playableWavPath;

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

  Future<String> _getFilePath() async {
    final dir = await getExternalStorageDirectory();
    int count = 1;
    String path = '';
    while (true) {
      path = '${dir!.path}/Undetermined_$count.aac';
      if (!await File(path).exists()) break;
      count++;
    }
    return path;
  }

  Future<void> startRecording() async {
    if (!isRecorderReady || isRecording) return;

    rawAacPath = await _getFilePath();
    titleController.text = rawAacPath!.split('/').last.split('.').first;

    await recorder.startRecorder(toFile: rawAacPath, codec: Codec.aacMP4);
    setState(() => isRecording = true);

    _showRecordingBottomSheet();
  }

  Future<void> stopRecording({bool discard = false}) async {
    if (!isRecorderReady || !isRecording) return;

    await recorder.stopRecorder();
    setState(() => isRecording = false);

    if (discard) {
      if (rawAacPath != null) File(rawAacPath!).delete();
      if (cleanedAacPath != null) File(cleanedAacPath!).delete();
      if (playableWavPath != null) File(playableWavPath!).delete();
      rawAacPath = null;
      cleanedAacPath = null;
      playableWavPath = null;
      titleController.clear();
    }
  }

  Future<Map<String, dynamic>> _sendToMLServer(String filePath) async {
    final uri = Uri.parse("https://etech-rgsx.onrender.com/predict");
    final request = http.MultipartRequest("POST", uri);
    request.files.add(await http.MultipartFile.fromPath(
      "file",
      filePath,
      contentType: MediaType('file', 'aac'),
    ));

    final response = await request.send();
    final respStr = await response.stream.bytesToString();

    if (response.statusCode != 200) {
      throw Exception("Server error: ${response.statusCode}");
    }

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
      builder: (context) => StatefulBuilder(builder: (context, setModalState) {
        Map<String, dynamic>? predictionData;

        return FractionallySizedBox(
          heightFactor: 0.7,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                RecordTitleField(
                  showTitleField: showExtraButtons,
                  titleController: titleController,
                ),
                const SizedBox(height: 20),

                // Recording timer
                StreamBuilder<RecordingDisposition>(
                  stream: recorder.onProgress,
                  builder: (context, snapshot) {
                    final duration = snapshot.hasData ? snapshot.data!.duration : Duration.zero;
                    final text =
                        '${duration.inMinutes.toString().padLeft(2, '0')}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
                    return Text(
                      text,
                      style: const TextStyle(fontSize: 50, color: Colors.white, fontWeight: FontWeight.bold),
                    );
                  },
                ),
                const SizedBox(height: 20),

                // STOP BUTTON
                if (!showExtraButtons)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        shape: const CircleBorder(),
                        padding: const EdgeInsets.all(20),
                        backgroundColor: secondColor),
                    onPressed: () async {
                      await stopRecording();
                      setModalState(() => isProcessingAudio = true);

                      try {
                        cleanedAacPath = await AudioProcessor.processAudio(rawAacPath!);
                        playableWavPath = await AudioProcessor.convertToWav(cleanedAacPath!);
                      } catch (e) {
                        cleanedAacPath = rawAacPath;
                        playableWavPath = rawAacPath;
                      }

                      setModalState(() {
                        isProcessingAudio = false;
                        showExtraButtons = true;
                      });
                    },
                    child: const Icon(Icons.stop, size: 30, color: Colors.white),
                  ),

                if (isProcessingAudio) ...[
                  const SizedBox(height: 20),
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 10),
                  const Text("Cleaning audio...", style: TextStyle(color: Colors.white)),
                ],

                const SizedBox(height: 20),

                // Audio Player
                if (showExtraButtons && playableWavPath != null)
                  AudioPlayerControls(audioPlayer: audioPlayerService, filePath: playableWavPath!),

                const SizedBox(height: 20),

                // Predict + Discard
                if (showExtraButtons)
                  Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isPredicting ? Colors.grey : Colors.blueAccent,
                              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                            ),
                            onPressed: (cleanedAacPath == null || isPredicting)
                                ? null
                                : () async {
                                    setState(() => isPredicting = true);
                                    try {
                                      final data = await _sendToMLServer(cleanedAacPath!);
                                      predictionData = data;

                                      Uint8List? wavBytes;
                                      if (data['wav_base64'] != "") {
                                        wavBytes = base64Decode(data['wav_base64']);
                                      }

                                      ResultBottomSheet.show(
                                        context,
                                        prediction: data["prediction"],
                                        confidence: data["confidence"]?.toDouble() ?? 0.0,
                                        rawBytes: wavBytes,
                                        baseName: titleController.text.trim(),
                                      );

                                      setModalState(() {});
                                    } catch (e) {
                                      ResultBottomSheet.show(
                                        context,
                                        prediction: "Prediction failed",
                                        confidence: 0.0,
                                        isError: true,
                                      );
                                    } finally {
                                      setState(() => isPredicting = false);
                                    }
                                  },
                            child: isPredicting
                                ? const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                                      ),
                                      SizedBox(width: 10),
                                      Text('Predicting...', style: TextStyle(color: Colors.white)),
                                    ],
                                  )
                                : const Text('Predict', style: TextStyle(color: Colors.white)),
                          ),

                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: const Color.fromARGB(255, 223, 111, 103),
                                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15)),
                            onPressed: () async {
                              await stopRecording(discard: true);
                              Navigator.pop(context);
                            },
                            child: const Text('Discard', style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      if (predictionData != null)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey[800],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              Text("Final Prediction: ${predictionData?['final_prediction'] ?? 'Unknown'}",
                                  style: const TextStyle(color: Colors.white, fontSize: 18)),
                              const SizedBox(height: 8),
                              Text("Male Clips: ${predictionData?['male_clips'] ?? 0}", style: const TextStyle(color: Colors.white70)),
                              Text("Female Clips: ${predictionData?['female_clips'] ?? 0}", style: const TextStyle(color: Colors.white70)),
                              Text(
                                  "Average Confidence: ${(predictionData?['average_confidence']?.toDouble() ?? 0.0).toStringAsFixed(2)}%",
                                  style: const TextStyle(color: Colors.white70)),
                            ],
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        );
      }),
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
