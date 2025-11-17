import 'dart:io';
import 'dart:math';
import 'package:etech/pages/MainPage.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'package:firebase_core/firebase_core.dart';
import 'package:path_provider/path_provider.dart';
import '../database/firebase_con.dart';
import '../database/firestore_con.dart';
import '../widgets/stateless/loading_screen.dart';
import 'package:lottie/lottie.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const GenderPredictorApp());
}

class GenderPredictorApp extends StatefulWidget {
  const GenderPredictorApp({super.key});

  @override
  State<GenderPredictorApp> createState() => _GenderPredictorAppState();
}

class _GenderPredictorAppState extends State<GenderPredictorApp> {
  bool loading = false;
  bool showConfetti = false;

  final FirebaseConnect _storageService = FirebaseConnect();
  final FirestoreConnect _firestoreService = FirestoreConnect();

  // Wake up server
  Future<void> wakeUpServer() async {
    try {
      var response =
          await http.get(Uri.parse("https://etech-rgsx.onrender.com/status"));
      if (response.statusCode == 200) {
        print("✅ Server is active and ready to predict");
      } else {
        print("⚠️ Server responded but not ready: ${response.statusCode}");
      }
    } catch (e) {
      print("❌ Server is sleeping or unreachable: $e");
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      wakeUpServer();
    });
  }

 void _showResultBottomSheet(
  String prediction,
  double confidence, {
  bool isError = false,
}) {
  Color bgColor;
  Color textColor = Colors.black87;

  // Clean formatted message
  String displayText = prediction;

  // 🔥 ERROR MODE
  if (isError) {
    bgColor = const Color(0xFFFF8A80); // pastel red
    textColor = Colors.white;

    displayText = prediction; 
  }

  // 🔵 NORMAL MODE
  else {
    if (prediction.toLowerCase() == 'female') {
      bgColor = const Color(0xFFFFC0CB); 
    } else if (prediction.toLowerCase() == 'male') {
      bgColor = const Color(0xFFADD8E6); 
    } else {
      bgColor = Colors.grey[900]!;
      textColor = Colors.white;
    }
  }

  // 🎉 Show confetti on success only
  setState(() => showConfetti = !isError);

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext context) {
      return FractionallySizedBox(
        heightFactor: 0.55,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                 
                  if (isError) ...[
                    const Text(
                      "An Error Occurred",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      displayText,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 18,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    Lottie.asset(
                      'assets/anim/error.json',
                      width: 160,
                      height: 160,
                      repeat: true,
                    ),
                  ]

             
                  else ...[
                    if (prediction.toLowerCase() == "female")
                      Lottie.asset(
                        'assets/anim/girl.json',
                        width: 160,
                        height: 160,
                        repeat: true,
                      )
                    else if (prediction.toLowerCase() == "male")
                      Lottie.asset(
                        'assets/anim/boy.json',
                        width: 160,
                        height: 160,
                        repeat: true,
                      ),

                    Text(
                      prediction,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "Confidence: ${confidence.toStringAsFixed(2)}%",
                      style: TextStyle(
                        color: textColor,
                        fontSize: 18,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],

                  const SizedBox(height: 25),

                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: secondColor,
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      "Try Again",
                      style: TextStyle(color: Colors.black),
                    ),
                  ),
                ],
              ),

              // 🎉 Confetti animation for success only
              if (!isError && showConfetti)
                Lottie.asset(
                  'assets/anim/confetti.json',
                  width: 220,
                  height: 220,
                  repeat: false,
                  onLoaded: (composition) {
                    Future.delayed(composition.duration, () {
                      if (mounted) {
                        setState(() => showConfetti = false);
                      }
                    });
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}

Future<File> convertMp3ToWav(File mp3File) async {
  final dir = await getTemporaryDirectory();
  String wavPath = '${dir.path}/${mp3File.uri.pathSegments.last.split(".").first}.wav';

  // FFmpeg command: mono, 16kHz, max 10 seconds
  String cmd = '-i "${mp3File.path}" -ar 16000 -ac 1 -t 10 "$wavPath"';

  await FFmpegKit.execute(cmd);

  return File(wavPath);
}


  // Pick audio and send to server
Future<void> _pickAndSendFile() async {
  FilePickerResult? resultPicker =
      await FilePicker.platform.pickFiles(type: FileType.audio);
  if (resultPicker == null) return;

  File file = File(resultPicker.files.single.path!);

  // Convert MP3 to WAV if needed
  if (file.path.toLowerCase().endsWith(".mp3")) {
    file = await convertMp3ToWav(file);
  }

  setState(() {
    loading = true;
  });

  // Show loader
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const LoadingScreen(
      animationAsset: 'assets/anim/loading2.json',
      message: "Analyzing audio...",
      backgroundColor: secondColor,
      textColor: textcolor,
    ),
  );

  try {
    var request = http.MultipartRequest(
      'POST',
      Uri.parse("https://etech-rgsx.onrender.com/predict"),
    );
    request.files.add(await http.MultipartFile.fromPath('audio', file.path));
    var response = await request.send();
    var respStr = await response.stream.bytesToString();

    if (response.statusCode == 200) {
      var data = json.decode(respStr);
      String prediction = data['prediction'];
      prediction = prediction[0].toUpperCase() + prediction.substring(1);
      double confidence = data['confidence'];

      Uint8List wavBytes = base64Decode(data['wav_base64']);
      String originalName = file.path.split('/').last.split('.').first;
      String fileName = "${prediction}_$originalName.wav";

      String downloadUrl = await _storageService.uploadBytes(
        wavBytes,
        fileName,
        prediction,
      );

      await _firestoreService.savePrediction(
        prediction: prediction,
        confidence: confidence,
        downloadUrl: downloadUrl,
        filePath: file.path,
      );

      Navigator.pop(context); // close loader

      setState(() {
        showConfetti = true;
      });

      _showResultBottomSheet(prediction, confidence);
    } else {
      Navigator.pop(context);
      _showResultBottomSheet("Server Error", 0.0, isError: true);
    }
  } catch (e) {
    Navigator.pop(context);
    _showResultBottomSheet("Error: $e", 0.0, isError: true);
  } finally {
    setState(() {
      loading = false;
    });
  }
}

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: backgroundColor,
        body: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: loading ? null : _pickAndSendFile,
                    child: Container(
                      width: double.infinity,
                      height: 360,
                      decoration: BoxDecoration(
                        color: Colors.grey[850],
                        borderRadius: BorderRadius.circular(36),
                        border: Border.all(
                            color: const Color.fromARGB(255, 240, 234, 159),
                            width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: const Color.fromARGB(255, 240, 234, 159),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.upload_file,
                                size: 55,
                                color: Color.fromARGB(255, 240, 234, 159)),
                            SizedBox(height: 12),
                            Text(
                              "Tap to select audio file",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 21),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
