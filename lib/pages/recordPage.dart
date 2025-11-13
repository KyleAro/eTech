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


class RecordPage extends StatefulWidget {
  @override
  _RecordPageState createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {
  final recorder = FlutterSoundRecorder();
  TextEditingController titleController = TextEditingController();
  final FirebaseConnect _storageService = FirebaseConnect();
  final FirestoreConnect _firestoreService = FirestoreConnect();

  bool isRecorderReady = false;
  bool isRecording = false;
  String? filePath;

  @override
  void initState() {
    super.initState();
    
    initRecorder();
     wakeUpServer();
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
Future<void> wakeUpServer() async {
  try {
    var response = await http.get(Uri.parse("https://etech-3a97.onrender.com/predict"));
    print("Server wake-up status: ${response.statusCode}");
  } catch (e) {
    print("Server still sleeping...");
  }
}
  void _showRecordingBottomSheet() {
  bool showExtraButtons = false;
  bool predictionDone = false;
  bool loadingPrediction = false; // Prevent spam clicks
  String? cleanedFilePath;
  String? predictionResult;
  final bottomSheetAudioPlayer = AudioPlayerService();

  showModalBottomSheet(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return WillPopScope(
        onWillPop: () async => false,
        child: StatefulBuilder(
          builder: (context, setModalState) {
            return FractionallySizedBox(
              heightFactor: 0.8,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
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
                        final duration = snapshot.hasData
                            ? snapshot.data!.duration
                            : Duration.zero;
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
                          await stopRecording();
                          String processedFile = filePath!;
                          try {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text("Processing audio...")),
                            );
                            processedFile =
                                await AudioProcessor.process(filePath!);
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
                    // Audio player controls
                    if (showExtraButtons && cleanedFilePath != null)
                      AudioPlayerControls(
                        audioPlayer: bottomSheetAudioPlayer,
                        filePath: cleanedFilePath!,
                      ),
                    const SizedBox(height: 20),
                    // Predict button
                    if (showExtraButtons)
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 40, vertical: 15),
                        ),
                        onPressed: predictionDone || loadingPrediction
                            ? null
                            : () async {
                                if (cleanedFilePath != null &&
                                    await File(cleanedFilePath!).exists()) {
                                  setModalState(() => loadingPrediction = true);
                                  showDialog(
                                                context: context,
                                                barrierDismissible: false,
                                                builder: (context) => const Center(
                                                  child: CircularProgressIndicator(
                                                    color: Color.fromARGB(255, 168, 175, 76),
                                                    strokeWidth: 5,
                                                  ),
                                                ),
                                              );

                                  try {
                                    var request = http.MultipartRequest(
                                      'POST',
                                      Uri.parse(
                                          "https://etech-3a97.onrender.com/predict"),
                                    );
                                    request.files.add(
                                        await http.MultipartFile.fromPath(
                                      'file',
                                      cleanedFilePath!,
                                    ));

                                    var response = await request.send();
                                    var respStr =
                                        await response.stream.bytesToString();

                                    if (response.statusCode == 200) {
                                      var data = json.decode(respStr);
                                      String prediction = data['prediction'];
                                      double confidence = data['confidence'];
                                      predictionResult =
                                          "$prediction (${confidence.toStringAsFixed(2)}%)";

                                      // Show dialog with Save option
                                      showDialog(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title:
                                              const Text("Prediction Result"),
                                          content: Text(predictionResult!),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context),
                                              child: const Text("OK"),
                                            ),
                                            TextButton(
                                              onPressed: () async {
                                                final directory =
                                                    await getExternalStorageDirectory();
                                                final savePath =
                                                    '${directory!.path}/${titleController.text.trim()}.wav';
                                                await File(cleanedFilePath!)
                                                    .copy(savePath);

                                                Navigator.pop(context); // close dialog
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                        'Recording saved locally as "${savePath.split('/').last}"'),
                                                  ),
                                                );
                                              },
                                              child: const Text("Save"),
                                            ),
                                          ],
                                        ),
                                      );
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                            content: Text(
                                                "Server Error: ${response.statusCode}")),
                                      );
                                    }
                                  } catch (e) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text("Error: $e")),
                                    );
                                  }

                                  setModalState(() {
                                    predictionDone = true;
                                    loadingPrediction = false;
                                  });
                                }
                              },
                        child: const Text(
                          'Predict',
                          style: TextStyle(color: Colors.white),
                        ),
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