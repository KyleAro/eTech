import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../style/mainpage_style.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import '../widgets/stateless/recordtitle.dart';
import '../database/firebase_con.dart';
import '../database/firestore_con.dart';
import '../widgets/stateful/audioplayer.dart';
import '../widgets/stateful/audio_cleaner.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';

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

  @override
  void initState() {
    super.initState();
    initRecorder();
  }

  @override
  void dispose() {
    recorder.closeRecorder();
    super.dispose();
  }

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

  Future<void> stopRecording() async {
    if (!isRecorderReady || !isRecording) return;
    await recorder.stopRecorder();
    setState(() => isRecording = false);
  }
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
void _showPredictionDialog(String gender, double confidence) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text("Prediction Result"),
      content: Text(
        "Gender: $gender\nConfidence: ${confidence.toStringAsFixed(2)}%",
      ),
      actions: [
        TextButton(
          child: Text("OK"),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    ),
  );
}
  void _showRecordingBottomSheet() {
  bool showExtraButtons = false;
  String? cleanedFilePath;
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
                    // Timer
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
                    // Stop button
                    if (!showExtraButtons)
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          shape: const CircleBorder(),
                          padding: const EdgeInsets.all(20),
                          backgroundColor: Colors.orangeAccent,
                        ),
                        onPressed: () async {
                          await stopRecording();
                          String processedFile = filePath!;
                          try {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Processing audio...")),
                            );

                            processedFile = await AudioProcessor.process(filePath!);
                          } catch (e) {
                            print("Audio processing failed: $e");
                            processedFile = filePath!;
                          }

                          filePath = processedFile;
                          cleanedFilePath = processedFile;

                          setModalState(() => showExtraButtons = true);
                        },
                        child: const Icon(
                          Icons.stop,
                          size: 30,
                          color: Colors.white,
                        ),
                      ),
                    const SizedBox(height: 20),
                    if (showExtraButtons && cleanedFilePath != null)
                      AudioPlayerControls(
                        audioPlayer: bottomSheetAudioPlayer,
                        filePath: cleanedFilePath!,
                      ),
                    const SizedBox(height: 20),
                    // Save / Discard buttons
                    if (showExtraButtons)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          
                               ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isPredicting ? Colors.grey : Colors.blueAccent,
                                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                                    ),
                                    onPressed: (cleanedFilePath == null || isPredicting) 
                                        ? null 
                                        : () async {
                                            setState(() => isPredicting = true); // disable button

                                            try {
                                              // STEP 1: Send file to server
                                              final predictionData = await _sendToMLServer(cleanedFilePath!);

                                              // STEP 2: Decode WAV returned by server
                                              Uint8List wavBytes = base64Decode(predictionData['wav_base64']);

                                              // STEP 3: Generate filename
                                              String baseName = titleController.text.trim();
                                              String gender = predictionData['prediction'];
                                              String fileName = "${gender}_${baseName}.wav";

                                              // STEP 4: Upload WAV to Firebase Storage
                                              String downloadUrl = await _storageService.uploadBytes(
                                                wavBytes,
                                                fileName,
                                                gender,
                                              );

                                              // STEP 5: Save to Firestore
                                              await _firestoreService.savePrediction(
                                                prediction: gender,
                                                confidence: predictionData["confidence"],
                                                downloadUrl: downloadUrl,
                                                filePath: baseName,
                                              );

                                              // STEP 6: Show prediction dialog
                                              _showPredictionDialog(
                                                gender,
                                                predictionData["confidence"],
                                              );
                                            } catch (e) {
                                              print("Prediction error: $e");
                                            } finally {
                                              setState(() => isPredicting = false); // re-enable button
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

                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color.fromARGB(255, 223, 111, 103),
                              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                            ),
                            onPressed: () async {
                              try {
                                final directory = await getExternalStorageDirectory();
                                final baseName = titleController.text.trim();

                                if (filePath != null && await File(filePath!).exists()) {
                                  await File(filePath!).delete();
                                  print("🗑️ Deleted temp AAC file: ${filePath!}");
                                }

                                if (cleanedFilePath != null && await File(cleanedFilePath!).exists()) {
                                  await File(cleanedFilePath!).delete();
                                  print("🗑️ Deleted cleaned WAV file: ${cleanedFilePath!}");
                                }

                                final files = directory!.listSync();
                                for (var file in files) {
                                  if (file is File &&
                                      (file.path.endsWith(".aac") || file.path.endsWith(".wav")) &&
                                      file.path.contains(baseName)) {
                                    await file.delete();
                                    print("🧽 Cleaned leftover file: ${file.path}");
                                  }
                                }

                                setState(() {
                                  isRecording = false;
                                  titleController.clear();
                                  filePath = null;
                                  cleanedFilePath = null;
                                });

                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Recording discarded'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );

                                Navigator.pop(context); // close sheet
                              } catch (e) {
                                print("⚠️ Error discarding files: $e");
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error deleting files: $e')),
                                );
                              }
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


@override
Widget build(BuildContext context) {
  return Scaffold(
    body: Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
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
      ],
    ),
    ),
  );
}
}