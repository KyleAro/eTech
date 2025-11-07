import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

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

  // Upload audio to Firebase Storage
  Future<String> uploadToPrediction(String path, String gender) async {
    try {
      final folderName =
          gender.toLowerCase() == 'male' ? 'Male Ducklings' : 'Female Ducklings';
      final storageRef = FirebaseStorage.instance.ref().child(folderName);
      final originalName = path.split('/').last;
      final fileName = "${gender}_$originalName";
      final fileRef = storageRef.child(fileName);

      await fileRef.putFile(File(path));
      final downloadUrl = await fileRef.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      print("Upload error: $e");
      return '';
    }
  }

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
      var request = http.MultipartRequest(
          'POST', Uri.parse("http://192.168.1.8:5000/predict"));
      request.files.add(await http.MultipartFile.fromPath('file', file.path));
      var response = await request.send();
      var respStr = await response.stream.bytesToString();

      Navigator.pop(context); // close loader

      if (response.statusCode == 200) {
        var data = json.decode(respStr);
        String prediction = data['prediction'];
        double confidence = data['confidence'];

        String downloadUrl = await uploadToPrediction(file.path, prediction);

        String collectionName =
            prediction.toLowerCase() == 'male' ? 'Male Ducklings' : 'Female Ducklings';
        String category = "${prediction} Ducklings";
        String originalName = file.path.split('/').last;
        String renamedFile = "${prediction}_$originalName";

        await FirebaseFirestore.instance
            .collection(collectionName)
            .doc(renamedFile)
            .set({
          'File_Name': renamedFile,
          'Category': category,
          'Previous Prediction': 'Undetermined Ducklings',
          'Final Prediction': prediction,
          'Confidence_Percentage': confidence,
          'Url': downloadUrl,
          'Timestamp': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // Update result string to show below button
        setState(() {
          result = "✅ Prediction: $prediction\nConfidence: ${confidence.toStringAsFixed(2)}%";
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
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text("Gender Pitch Detector"),
          backgroundColor: Colors.black87,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: loading ? null : _pickAndSendFile,
                  style: ElevatedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    backgroundColor: Colors.blueAccent,
                  ),
                  child: const Text(
                    "Select Audio File",
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  result,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
