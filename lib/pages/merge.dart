import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:etech/pages/MainPage.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:path_provider/path_provider.dart';
import '../database/firebase_con.dart';
import '../database/firestore_con.dart';
import '../widgets/stateless/loading_screen.dart';
import 'package:lottie/lottie.dart';
import '../widgets/stateless/result_botsheet.dart'; // Reusable bottom sheet

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
  bool serverReady = false;
  Timer? statusTimer;

  final FirebaseConnect _storageService = FirebaseConnect();
  final FirestoreConnect _firestoreService = FirestoreConnect();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      wakeUpServer();
      // Optional: auto-refresh every 15 seconds
      statusTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
        if (mounted) wakeUpServer();
      });
    });
  }

  @override
  void dispose() {
    statusTimer?.cancel();
    super.dispose();
  }

  // Wake up server & update banner status
  Future<void> wakeUpServer() async {
    try {
      var response = await http.get(Uri.parse("https://etech-rgsx.onrender.com/status"));
      if (response.statusCode == 200) {
        setState(() => serverReady = true);
        print("✅ Server is active and ready to predict");
      } else {
        setState(() => serverReady = false);
        print("⚠️ Server responded but not ready: ${response.statusCode}");
      }
    } catch (e) {
      setState(() => serverReady = false);
      print("❌ Server is sleeping or unreachable: $e");
    }
  }

  // Server status banner
  Widget serverStatusBanner() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      width: double.infinity,
      color: serverReady ? Colors.green[400] : Colors.red[400],
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            serverReady ? Icons.check_circle : Icons.error,
            color: Colors.white,
          ),
          const SizedBox(width: 8),
          Text(
            serverReady ? "Server Ready" : "Server Sleeping",
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  // ✅ Replaced showResultBottomSheet with reusable bottom sheet
  void _showResultBottomSheet(String prediction, double confidence, {bool isError = false}) {
    ResultBottomSheet.show(
      context,
      prediction: prediction,
      confidence: confidence,
      isError: isError,
    );
  }

  Future<void> _pickAndSendFile() async {
    // Pick audio file
    FilePickerResult? resultPicker =
        await FilePicker.platform.pickFiles(type: FileType.audio);

    if (resultPicker == null) return; // user canceled

    File? file;
    final pickedFile = resultPicker.files.single;

    // Safely handle file path or bytes
    if (pickedFile.path != null) {
      file = File(pickedFile.path!);
    } else if (pickedFile.bytes != null) {
      final dir = await getTemporaryDirectory();
      final tempFile = File('${dir.path}/${pickedFile.name}');
      await tempFile.writeAsBytes(pickedFile.bytes!);
      file = tempFile;
    } else {
      _showResultBottomSheet("Invalid file selected", 0.0, isError: true);
      return;
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

      request.files.add(await http.MultipartFile.fromPath('file', file.path));
      var response = await request.send();
      var respStr = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        var data = json.decode(respStr);
        String prediction = data['prediction'];
        prediction = prediction[0].toUpperCase() + prediction.substring(1);
        double confidence = data['confidence'];

        Navigator.pop(context); // close loader
        _showResultBottomSheet(prediction, confidence);
      } else {
        Navigator.pop(context);
        _showResultBottomSheet("Server Error", 0.0, isError: true);
      }
    } catch (e) {
      Navigator.pop(context);
      _showResultBottomSheet("", 0.0, isError: true);
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
        body: Column(
          children: [
            // ✅ Server status banner only on this page
            serverStatusBanner(),
            Expanded(
              child: Center(
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
                                    style: TextStyle(color: Colors.white70, fontSize: 21),
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
          ],
        ),
      ),
    );
  }
}
