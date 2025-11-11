import 'dart:io';
import 'package:etech/pages/MainPage.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import '../database/firebase_con.dart';
import '../database/firestore_con.dart';

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
  String result = "";
  bool loading = false;

  final FirebaseConnect _storageService = FirebaseConnect();
  final FirestoreConnect _firestoreService = FirestoreConnect();

  Future<void> _pickAndSendFile() async {
    FilePickerResult? resultPicker =
        await FilePicker.platform.pickFiles(type: FileType.audio);
    if (resultPicker == null) return;

    File file = File(resultPicker.files.single.path!);
    setState(() {
      loading = true;
      result = "";
    });

    // Loader dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              color: Color.fromARGB(255, 243, 255, 68),
              strokeWidth: 5,
            ),
            SizedBox(height: 15),
            Text(
              "Analyzing audio...",
              style: TextStyle(color: Colors.white, fontSize: 16),
            )
          ],
        ),
      ),
    );

    try {
      var request =
          http.MultipartRequest('POST', Uri.parse("http://192.168.1.9:5000/predict"));
      request.files.add(await http.MultipartFile.fromPath('file', file.path));
      var response = await request.send();
      var respStr = await response.stream.bytesToString();

      Navigator.pop(context); // close loader

      if (response.statusCode == 200) {
        var data = json.decode(respStr);
        String prediction = data['prediction'];
        double confidence = data['confidence'];

        // ✅ Upload audio to Firebase Storage
        String downloadUrl =
            await _storageService.uploadToPrediction(file.path, prediction);

        // ✅ Save data to Firestore
        await _firestoreService.savePrediction(
          prediction: prediction,
          confidence: confidence,
          downloadUrl: downloadUrl,
          filePath: file.path,
        );

        // ✅ Show result
        setState(() {
          result =
              "✅ Prediction: $prediction\nConfidence: ${confidence.toStringAsFixed(2)}%";
        });
      } else {
        setState(() {
          result = "❌ Server Error: ${response.statusCode}";
        });
      }
    } catch (e) {
      Navigator.pop(context);
      setState(() {
        result = "⚠️ Error: $e";
      });
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
      appBar: AppBar(
        title: const Text("Gender Pitch Detector"),
        backgroundColor: const Color.fromARGB(221, 235, 224, 224),
        elevation: 2,
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Upload Container
                GestureDetector(
                  onTap: loading ? null : _pickAndSendFile,
                  child: Container(
                    width: double.infinity,
                    height: 160,
                    decoration: BoxDecoration(
                      color: Colors.grey[850],
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.blueAccent, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blueAccent.withOpacity(0.2),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.upload_file, size: 55, color: Colors.blueAccent),
                          SizedBox(height: 12),
                          Text(
                            "Tap to select audio file",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white70, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 25),

                // Loader / Progress Indicator
                if (loading)
                  const LinearProgressIndicator(
                    backgroundColor: Colors.grey,
                    color: Colors.blueAccent,
                    minHeight: 6,
                  ),

                const SizedBox(height: 25),

                // Result Box
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[850],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.blueAccent.withOpacity(0.4)),
                  ),
                  child: Text(
                    result.isEmpty ? "No result yet" : result,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),

                const SizedBox(height: 25),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

}