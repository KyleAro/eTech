import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';


class Upload extends StatefulWidget {
  @override
  _UploadState createState() => _UploadState();
}

class _UploadState extends State<Upload> {
  final recorder = FlutterSoundRecorder();
  bool isRecorderReady = false;
  bool isRecording = false;
  bool showSaveDiscard = false;
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
      uniquePath = '${directory!.path}/Recording_$count.aac';
      if (!await File(uniquePath).exists()) break;
      count++;
    }
    return uniquePath;
  }

  Future<void> startRecording() async {
    if (!isRecorderReady) return;
    if (filePath != null) return;

    filePath = await getFilePath();
    await recorder.startRecorder(toFile: filePath);
    setState(() {
      isRecording = true;
      showSaveDiscard = false;
    });

    _showRecordingBottomSheet();
  }

  Future<void> stopRecording() async {
    if (!isRecorderReady) return;
    await recorder.stopRecorder();
    setState(() {
      isRecording = false;
      showSaveDiscard = true;
    });
  }

  void _showRecordingBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return FractionallySizedBox(
              heightFactor: 0.5,
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // ✅ Timer widget
                   
                    SizedBox(height: 30),

                    // Stop button
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        shape: CircleBorder(),
                        padding: EdgeInsets.all(20),
                        backgroundColor: Colors.orangeAccent,
                      ),
                      onPressed: () async {
                        await stopRecording();
                        setModalState(() {}); // show Save/Discard
                      },
                      child: Icon(Icons.stop, size: 30, color: Colors.white),
                    ),
                    SizedBox(height: 20),

                    // Save / Discard buttons
                    if (showSaveDiscard)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              padding: EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 15),
                            ),
                            onPressed: () {
                              print('Save pressed: $filePath');
                              Navigator.pop(context);
                            },
                            child: Text('Save',
                                style: TextStyle(color: Colors.white)),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color.fromARGB(255, 221, 130, 124),
                              padding: EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 15),
                            ),
                            onPressed: () {
                              print('Discard pressed: $filePath');
                              Navigator.pop(context);
                            },
                            child: Text('Discard',
                                style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.red,
      body: Center(
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orangeAccent,
            shape: CircleBorder(),
            padding: EdgeInsets.all(20),
          ),
          onPressed: () async {
            if (!isRecorderReady) await initRecorder();
            await startRecording();
          },
          child: Icon(Icons.play_arrow, size: 30, color: Colors.white),
        ),
      ),
    );
  }
}
