import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../style/mainpage_style.dart';
import '../widgets/stateless/recordtitle.dart';
import '../widgets/stateful/audioplayer.dart';
import '../widgets/stateful/audio_cleaner.dart';
import '../database/firebase_con.dart';
import '../database/firestore_con.dart';

class RecordPage extends StatefulWidget {
  @override
  _RecordPageState createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {
  final recorder = FlutterSoundRecorder();
  TextEditingController titleController = TextEditingController();
  final FirebaseConnect _storageService = FirebaseConnect();
  final FirestoreConnect _firestoreService = FirestoreConnect();

  bool isPredicting = false;
  bool isRecorderReady = false;
  bool isRecording = false;
  String? filePath;
  String? cleanedFilePath;

  // ---------- Server status ----------
  bool serverReady = false;
  bool checkingServer = true;

  @override
  void initState() {
    super.initState();
    initRecorder();
    _checkServerOnStart(); // check server immediately
  }

  @override
  void dispose() {
    recorder.closeRecorder();
    super.dispose();
  }

  // -------------------------- Recorder setup --------------------------
  Future<void> initRecorder() async {
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      throw 'Microphone permission not granted';
    }
    await recorder.openRecorder();
    isRecorderReady = true;
    recorder.setSubscriptionDuration(const Duration(milliseconds: 500));
  }

  Future<String> getFilePath() async {
    final directory = await getExternalStorageDirectory();
    int count = 1;
    String uniquePath = '';
    while (true) {
      uniquePath = '${directory!.path}/Undetermined_$count.aac';
      if (!await File(uniquePath).exists()) break;
      count++;
    }
    return uniquePath;
  }

  Future<void> startRecording() async {
    if (!isRecorderReady || filePath != null) return;

    filePath = await getFilePath();
    final fileName = filePath!.split('/').last;
    titleController.text = fileName.split('.').first;

    await recorder.startRecorder(toFile: filePath);
    setState(() => isRecording = true);

    _showRecordingBottomSheet();
  }

  Future<void> stopRecording({bool discard = false}) async {
    if (!isRecorderReady || !isRecording) return;

    await recorder.stopRecorder();
    setState(() => isRecording = false);

    if (discard) {
      if (filePath != null && await File(filePath!).exists()) {
        await File(filePath!).delete();
      }
      if (cleanedFilePath != null && await File(cleanedFilePath!).exists()) {
        await File(cleanedFilePath!).delete();
      }

      setState(() {
        filePath = null;
        cleanedFilePath = null;
        titleController.clear();
      });
    }
  }

  // -------------------------- Server check --------------------------
  Future<void> _checkServerOnStart() async {
    setState(() => checkingServer = true);
    try {
      final uri = Uri.parse("https://etech-rgsx.onrender.com/status");
      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        bool isReady = data['status'] == 'Server is running';
        setState(() => serverReady = isReady);

        if (isReady) {
          ScaffoldMessenger.of(context).showMaterialBanner(
            MaterialBanner(
              content: const Text(
                "✅ Server is active and ready",
                style: TextStyle(color: Colors.white),
              ),
              backgroundColor: Colors.green[700],
              actions: [
                TextButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
                  },
                  child: const Text("DISMISS", style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          );
        }
      } else {
        setState(() => serverReady = false);
      }
    } catch (e) {
      print("Server check failed: $e");
      setState(() => serverReady = false);
    } finally {
      setState(() => checkingServer = false);
    }
  }

  // -------------------------- Save WAV to external storage --------------------------
  Future<String> saveCleanedWav(String wavPath, String baseName) async {
  final directory = await getExternalStorageDirectory();
  final savedPath = '${directory!.path}/$baseName.wav';
  final file = File(wavPath);
  await file.copy(savedPath); // Copy the file
  return savedPath; // Return the path as String
}

  // -------------------------- ML Server --------------------------
  Future<Map<String, dynamic>> _sendToMLServer(String filePath) async {
    final uri = Uri.parse("https://etech-rgsx.onrender.com/predict");

    final request = http.MultipartRequest("POST", uri);
    request.files.add(await http.MultipartFile.fromPath("audio", filePath));

    final response = await request.send();

    if (response.statusCode != 200) {
      throw Exception("Server error: ${response.statusCode}");
    }

    final respStr = await response.stream.bytesToString();
    return jsonDecode(respStr);
  }

  // -------------------------- Prediction dialog --------------------------
  void _showPredictionDialog(String gender, double confidence) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text("Prediction Result"),
        content: Text(
          "Gender: $gender\nConfidence: ${confidence.toStringAsFixed(2)}%",
        ),
        actions: [
          TextButton(
            child: const Text("Save"),
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
              setState(() {
                isRecording = false;
                filePath = null;
                cleanedFilePath = null;
                titleController.clear();
              });
            },
          ),
        ],
      ),
    );
  }

  // -------------------------- Bottom sheet --------------------------
  void _showRecordingBottomSheet() {
    bool showExtraButtons = false;
    final bottomSheetAudioPlayer = AudioPlayerService();

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return WillPopScope(
          onWillPop: () async => !isPredicting,
          child: StatefulBuilder(
            builder: (context, setModalState) {
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
                      RecordTitleField(
                        showTitleField: showExtraButtons,
                        titleController: titleController,
                      ),
                      const SizedBox(height: 20),
                      StreamBuilder<RecordingDisposition>(
                        stream: recorder.onProgress,
                        builder: (context, snapshot) {
                          final duration = snapshot.hasData ? snapshot.data!.duration : Duration.zero;
                          final text =
                              '${duration.inMinutes.toString().padLeft(2, '0')}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
                          return Text(
                            text,
                            style: const TextStyle(
                              fontSize: 50,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      // Stop recording button
                      if (!showExtraButtons)
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            shape: const CircleBorder(),
                            padding: const EdgeInsets.all(20),
                            backgroundColor: Colors.orangeAccent,
                          ),
                          onPressed: () async {
                            // Stop recording (.aac)
                            await stopRecording();

                            String wavPath = '';
                            try {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Processing audio...")),
                              );

                              // Process AAC → cleaned WAV
                              wavPath = await AudioProcessor.process(filePath!);
                              // Save permanently
                              String baseName = titleController.text.trim();
                              cleanedFilePath = await saveCleanedWav(wavPath, baseName);

                            } catch (e) {
                              print("Audio processing failed: $e");
                              cleanedFilePath = filePath; // fallback
                            }

                            // Show extra buttons
                            setModalState(() => showExtraButtons = true);
                          },
                          child: const Icon(
                            Icons.stop,
                            size: 30,
                            color: Colors.white,
                          ),
                        ),
                      const SizedBox(height: 20),
                      // Playback controls
                      if (showExtraButtons && cleanedFilePath != null)
                        AudioPlayerControls(
                          audioPlayer: bottomSheetAudioPlayer,
                          filePath: cleanedFilePath!,
                        ),
                      const SizedBox(height: 20),
                      // Predict / Discard buttons
                      if (showExtraButtons)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // Predict
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isPredicting ? Colors.grey : Colors.blueAccent,
                                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                              ),
                              onPressed: (cleanedFilePath == null || isPredicting)
                                  ? null
                                  : () async {
                                      setState(() => isPredicting = true);
                                      try {
                                        final predictionData = await _sendToMLServer(cleanedFilePath!);
                                        Uint8List wavBytes = base64Decode(predictionData['wav_base64']);

                                        String baseName = titleController.text.trim();
                                        String gender = predictionData['prediction'];
                                        String fileName = "${gender}_${baseName}.wav";

                                        // Upload WAV to Firebase
                                        String downloadUrl = await _storageService.uploadBytes(
                                          wavBytes,
                                          fileName,
                                          gender,
                                        );

                                        await _firestoreService.savePrediction(
                                          prediction: gender,
                                          confidence: predictionData["confidence"],
                                          downloadUrl: downloadUrl,
                                          filePath: baseName,
                                        );

                                        _showPredictionDialog(
                                          gender,
                                          predictionData["confidence"],
                                        );
                                      } catch (e) {
                                        print("Prediction error: $e");
                                      } finally {
                                        setState(() => isPredicting = false);
                                      }
                                    },
                              child: isPredicting
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            color: Colors.white,
                                          ),
                                        ),
                                        SizedBox(width: 10),
                                        Text(
                                          'Predicting...',
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ],
                                    )
                                  : const Text(
                                      'Predict',
                                      style: TextStyle(color: Colors.white),
                                    ),
                            ),
                            // Discard
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color.fromARGB(255, 223, 111, 103),
                                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                              ),
                              onPressed: () async {
                                // Delete AAC + WAV
                                await stopRecording(discard: true);

                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Recording discarded'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                              child: const Text(
                                'Discard',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  // -------------------------- Build --------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: Center(
                  child: GestureDetector(
                    onTap: () async {
                      if (!isRecording) {
                        await startRecording();
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: 200,
                      width: 200,
                      child: NeuBox(
                        isPressed: isRecording,
                        child: Icon(
                          isRecording ? Icons.stop : Icons.mic,
                          size: 100,
                          color: const Color.fromARGB(255, 0, 0, 0),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          // --- Loading overlay while predicting ---
          if (isPredicting)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    CircularProgressIndicator(
                      color: Colors.white,
                    ),
                    SizedBox(height: 20),
                    Text(
                      "Predicting...",
                      style: TextStyle(color: Colors.white, fontSize: 18),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
