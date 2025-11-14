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
        onWillPop: () async => false, 
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
                              backgroundColor: Colors.green,
                              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                            ),
                            onPressed: () async {
                              if (cleanedFilePath != null && await File(cleanedFilePath!).exists()) {
                                final directory = await getExternalStorageDirectory();
                                final savePath = '${directory!.path}/${titleController.text.trim()}.wav';
                                final savedFile = await File(cleanedFilePath!).copy(savePath);

                                try {
                                  final baseName = titleController.text.trim();
                                  final files = directory.listSync();
                                  for (var file in files) {
                                    if (file is File && file.path.endsWith(".aac") && file.path.contains(baseName)) {
                                      await file.delete();
                                      print("🗑️ Deleted matching AAC file: ${file.path}");
                                    }
                                  }
                                } catch (e) {
                                  print("⚠️ Error deleting AAC file: $e");
                                }

                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Trimmed recording saved locally as "${savedFile.path}"'),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );

                                setState(() {
                                  isRecording = false;
                                  filePath = null;
                                  cleanedFilePath = null;
                                  titleController.clear();
                                });

                                Navigator.pop(context); // close sheet
                              }
                            },
                            child: const Text(
                              'Save',
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