import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
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
import '../widgets/stateless/result_botsheet.dart';

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
  bool serverReady = false;
  Timer? statusTimer;

  final FirebaseConnect _storageService = FirebaseConnect();
  final FirestoreConnect _firestoreService = FirestoreConnect();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      wakeUpServer();
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

  Future<void> _pickAndSendFile() async {
    FilePickerResult? resultPicker =
        await FilePicker.platform.pickFiles(type: FileType.audio);

    if (resultPicker == null) return;

    File? file;
    final pickedFile = resultPicker.files.single;

    if (pickedFile.path != null) {
      file = File(pickedFile.path!);
    } else if (pickedFile.bytes != null) {
      final dir = await getTemporaryDirectory();
      final tempFile = File('${dir.path}/${pickedFile.name}');
      await tempFile.writeAsBytes(pickedFile.bytes!);
      file = tempFile;
    } else {
      ResultBottomSheet.show(
        context,
        prediction: "Invalid file selected",
        confidence: 0.0,
        isError: true,
      );
      return;
    }

    setState(() => loading = true);

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

      print("🔥 DEBUG - Response Status: ${response.statusCode}");
      print("🔥 DEBUG - Raw Response Body:");
      print(respStr);
      print("=" * 80);

      if (response.statusCode == 200) {
        var data = json.decode(respStr);
        
        print("🔥 DEBUG - Decoded JSON:");
        print("   Full data: $data");
        print("   Data type: ${data.runtimeType}");
        print("=" * 80);
        
        print("🔥 DEBUG - Individual Fields:");
        print("   status: ${data['status']}");
        print("   final_prediction: ${data['final_prediction']} (type: ${data['final_prediction']?.runtimeType})");
        print("   average_confidence: ${data['average_confidence']} (type: ${data['average_confidence']?.runtimeType})");
        print("   total_clips: ${data['total_clips']} (type: ${data['total_clips']?.runtimeType})");
        print("   male_clips: ${data['male_clips']} (type: ${data['male_clips']?.runtimeType})");
        print("   female_clips: ${data['female_clips']} (type: ${data['female_clips']?.runtimeType})");
        print("   prediction_summary length: ${data['prediction_summary']?.length}");
        print("=" * 80);
        
        // Check if response has error status
        if (data['status'] == 'error') {
          Navigator.pop(context);
          ResultBottomSheet.show(
            context,
            prediction: data['message'] ?? "Server error",
            confidence: 0.0,
            isError: true,
          );
          return;
        }
        
        // Parse prediction (handle lowercase from model)
        String prediction = (data['final_prediction'] ?? 'unknown').toString().toLowerCase();
        print("🔥 DEBUG - Raw prediction: $prediction");
        
        // Capitalize first letter
        if (prediction.isNotEmpty && prediction != 'unknown') {
          prediction = prediction[0].toUpperCase() + prediction.substring(1).toLowerCase();
        } else {
          prediction = 'Unknown';
        }
        
        // Parse confidence (handle int or double)
        double confidence = 0.0;
        var confValue = data['average_confidence'];
        if (confValue != null) {
          confidence = (confValue is int) ? confValue.toDouble() : (confValue as num).toDouble();
        }
        
        int totalClips = (data['total_clips'] ?? 0) as int;
        int maleClips = (data['male_clips'] ?? 0) as int;
        int femaleClips = (data['female_clips'] ?? 0) as int;
        List<dynamic> clipResults = data['prediction_summary'] ?? [];

        print("🔥 DEBUG - Final values:");
        print("   Prediction: $prediction");
        print("   Confidence: $confidence");
        print("   Total Clips: $totalClips");
        print("   Male Clips: $maleClips");
        print("   Female Clips: $femaleClips");
        print("   Clip Results count: ${clipResults.length}");

        final dateString =
            "${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}";
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final originalName = pickedFile.name.split('.').first;
        final newFileName = "${prediction}_${originalName}_${dateString}_$timestamp.wav";

        final fileBytes = await file.readAsBytes();
        
        // Upload to gender-specific folder
        final downloadUrl = await _storageService.uploadBytes(
          fileBytes,
          newFileName,
          prediction,
        );

        await _firestoreService.savePrediction(
          prediction: prediction,
          confidence: confidence,
          downloadUrl: downloadUrl,
          filePath: file.path,
        );

        Navigator.pop(context); // Close loading dialog

        // Show success snackbar
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to $prediction folder'),
            backgroundColor: Colors.green[700],
            behavior: SnackBarBehavior.floating,
          ),
        );

        // Show result with ALL data
        ResultBottomSheet.show(
          context,
          prediction: prediction,
          confidence: confidence,
          rawBytes: fileBytes,
          baseName: newFileName,
          totalClips: totalClips,
          maleClips: maleClips,
          femaleClips: femaleClips,
          clipResults: clipResults,
          showConfetti: true,
        );
      } else {
        Navigator.pop(context);
        ResultBottomSheet.show(
          context,
          prediction: "Server Error: ${response.statusCode}",
          confidence: 0.0,
          isError: true,
        );
      }
    } catch (e) {
      print("🔥 ERROR: $e");
      Navigator.pop(context);
      ResultBottomSheet.show(
        context,
        prediction: "Upload failed: $e",
        confidence: 0.0,
        isError: true,
      );
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFFFFD54F),
          secondary: const Color(0xFFFFD54F),
          surface: const Color(0xFF1E1E1E),
          background: const Color(0xFF121212),
        ),
      ),
      home: Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          backgroundColor: secondColor,
          elevation: 0,
          title: const Text(
            'Upload Audio',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 20,
            ),
          ),
          centerTitle: true,
        ),
        body: Column(
          children: [
            // Server Status Chip
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                child: Chip(
                  avatar: CircleAvatar(
                    backgroundColor: serverReady ? Colors.green : Colors.red,
                    radius: 6,
                  ),
                  label: Text(
                    serverReady ? 'Server Ready' : 'Server Sleeping',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  backgroundColor: Colors.grey[900],
                  side: BorderSide.none,
                ),
              ),
            ),
            
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Main Upload Card
                      Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: InkWell(
                          onTap: loading ? null : _pickAndSendFile,
                          borderRadius: BorderRadius.circular(24),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(48),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFD54F).withOpacity(0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.cloud_upload_outlined,
                                    size: 80,
                                    color: Color(0xFFFFD54F),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                const Text(
                                  'Select Audio File',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Upload will automatically save to the correct folder',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[400],
                                  ),
                                ),
                                const SizedBox(height: 24),
                                FilledButton.icon(
                                  onPressed: loading ? null : _pickAndSendFile,
                                  icon: const Icon(Icons.folder_open),
                                  label: const Text('Browse Files'),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 32,
                                      vertical: 16,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 32),
                      
                      // Info Cards
                      Row(
                        children: [
                          Expanded(
                            child: _buildInfoCard(
                              icon: Icons.audiotrack,
                              title: 'Formats',
                              subtitle: 'MP3, WAV, AAC, M4A',
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildInfoCard(
                              icon: Icons.cloud_done,
                              title: 'Auto Save',
                              subtitle: 'Male/Female folders',
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Info card
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: const Color(0xFFFFD54F),
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Automatic Processing',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Files are predicted, renamed, and saved automatically',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[400],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: const Color(0xFFFFD54F),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[400],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}