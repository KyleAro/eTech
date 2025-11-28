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
import '../widgets/stateless/result_botsheet.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  // API Configuration
  static const String API_BASE_URL = "https://etech-rgsx.onrender.com";
  static const Duration REQUEST_TIMEOUT = Duration(seconds: 90);

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
      var response = await http
          .get(Uri.parse("$API_BASE_URL/status"))
          .timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        var data = json.decode(response.body);
        bool isReady = data['status'] == 'ready';
        
        if (mounted) {
          setState(() => serverReady = isReady);
        }
        
        if (isReady) {
          print("✅ Server is active and ready to predict");
        } else {
          print("⚠️ Server is warming up...");
        }
      } else {
        if (mounted) {
          setState(() => serverReady = false);
        }
        print("⚠️ Server responded with status: ${response.statusCode}");
      }
    } catch (e) {
      if (mounted) {
        setState(() => serverReady = false);
      }
      print("❌ Server is sleeping or unreachable: $e");
    }
  }

  Future<void> _pickAndSendFile() async {
    // Check if server is ready
    if (!serverReady) {
      _showErrorSnackBar('Server is still warming up. Please wait a moment.');
      return;
    }

    FilePickerResult? resultPicker =
        await FilePicker.platform.pickFiles(type: FileType.audio);

    if (resultPicker == null) return;

    File? file;
    final pickedFile = resultPicker.files.single;

    // Handle file path for different platforms
    if (pickedFile.path != null) {
      file = File(pickedFile.path!);
    } else if (pickedFile.bytes != null) {
      final dir = await getTemporaryDirectory();
      final tempFile = File('${dir.path}/${pickedFile.name}');
      await tempFile.writeAsBytes(pickedFile.bytes!);
      file = tempFile;
    } else {
      _showErrorDialog('Invalid file selected', 'Please select a valid audio file.');
      return;
    }

    // Validate file size (optional - e.g., 50MB max)
    final fileSize = await file.length();
    if (fileSize == 0) {
      _showErrorDialog('Empty File', 'The selected file is empty.');
      return;
    }
    if (fileSize > 50 * 1024 * 1024) {
      _showErrorDialog('File Too Large', 'Please select a file smaller than 50MB.');
      return;
    }

    setState(() => loading = true);

    // Show loading dialog
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
      // Prepare multipart request
      var request = http.MultipartRequest(
        'POST',
        Uri.parse("$API_BASE_URL/predict"),
      );
      
      request.files.add(await http.MultipartFile.fromPath('file', file.path));
      
      // Send request with timeout
      var streamedResponse = await request.send().timeout(
        REQUEST_TIMEOUT,
        onTimeout: () {
          throw TimeoutException('Upload timed out after ${REQUEST_TIMEOUT.inSeconds} seconds');
        },
      );
      
      var response = await http.Response.fromStream(streamedResponse);
      
      print("📡 Response Status: ${response.statusCode}");
      print("📡 Response Body: ${response.body}");

      if (response.statusCode == 200) {
        await _handleSuccessResponse(response.body, file, pickedFile.name);
      } else if (response.statusCode == 503) {
        Navigator.pop(context);
        _showErrorDialog('Server Busy', 'The server is still warming up. Please try again in a moment.');
      } else {
        Navigator.pop(context);
        var errorMsg = 'Server Error: ${response.statusCode}';
        try {
          var errorData = json.decode(response.body);
          errorMsg = errorData['message'] ?? errorMsg;
        } catch (_) {}
        _showErrorDialog('Prediction Failed', errorMsg);
      }
    } on TimeoutException catch (e) {
      print("⏱️ Timeout: $e");
      Navigator.pop(context);
      _showErrorDialog('Request Timeout', 'The request took too long. Please try again with a shorter audio file.');
    } on SocketException catch (e) {
      print("🌐 Network Error: $e");
      Navigator.pop(context);
      _showErrorDialog('Network Error', 'Please check your internet connection and try again.');
    } catch (e) {
      print("❌ Error: $e");
      Navigator.pop(context);
      _showErrorDialog('Upload Failed', 'An unexpected error occurred: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> _handleSuccessResponse(String responseBody, File file, String originalFileName) async {
    try {
      var data = json.decode(responseBody);
      
      // Check for error status in response
      if (data['status'] == 'error') {
        Navigator.pop(context);
        _showErrorDialog('Prediction Error', data['message'] ?? 'Unknown error occurred');
        return;
      }

      // Parse prediction (should already be Title Case from API)
      String prediction = (data['final_prediction'] ?? 'Unknown').toString().trim();
      
      // Validate prediction
      if (prediction != 'Male' && prediction != 'Female') {
        print("⚠️ Unexpected prediction value: $prediction");
        // Normalize just in case
        if (prediction.toLowerCase() == 'male') {
          prediction = 'Male';
        } else if (prediction.toLowerCase() == 'female') {
          prediction = 'Female';
        } else {
          prediction = 'Unknown';
        }
      }
      
      // Parse numeric values with safe type conversion
      double confidence = _parseDouble(data['average_confidence'], 0.0);
      int totalClips = _parseInt(data['total_clips'], 0);
      int maleClips = _parseInt(data['male_clips'], 0);
      int femaleClips = _parseInt(data['female_clips'], 0);
      List<dynamic> clipResults = data['prediction_summary'] ?? [];

      print("✅ Parsed Results:");
      print("   Prediction: $prediction");
      print("   Confidence: $confidence%");
      print("   Total Clips: $totalClips");
      print("   Male Clips: $maleClips");
      print("   Female Clips: $femaleClips");
      print("   Clip Results: ${clipResults.length}");

      // Generate new filename
      final dateString =
          "${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}";
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final originalName = originalFileName.split('.').first;
      final newFileName = "${prediction}_${originalName}_${dateString}_$timestamp.wav";

      // Read file bytes
      final fileBytes = await file.readAsBytes();
      
      // === SAVE LOCALLY ===
      await _saveLocalFile(fileBytes, newFileName, prediction, confidence, totalClips, maleClips, femaleClips, clipResults);
      
      // Upload to gender-specific folder in Firebase
      final downloadUrl = await _storageService.uploadBytes(
        fileBytes,
        newFileName,
        prediction,
      );

      // Save to Firestore
      await _firestoreService.savePrediction(
        prediction: prediction,
        confidence: confidence,
        downloadUrl: downloadUrl,
        filePath: file.path,
      );

      Navigator.pop(context); // Close loading dialog

      // Show success notification
      _showSuccessSnackBar('Saved to $prediction folder and local storage');

      // Show result bottom sheet
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
    } catch (e) {
      print("❌ Error parsing response: $e");
      Navigator.pop(context);
      _showErrorDialog('Parse Error', 'Failed to process server response: ${e.toString()}');
    }
  }

  // === NEW: SAVE FILE LOCALLY WITH METADATA ===
  Future<void> _saveLocalFile(
    List<int> fileBytes,
    String fileName,
    String prediction,
    double confidence,
    int totalClips,
    int maleClips,
    int femaleClips,
    List<dynamic> clipResults,
  ) async {
    try {
      // Get external storage directory
      final directory = await getExternalStorageDirectory();
      if (directory == null) {
        print("⚠️ External storage not available");
        return;
      }

      // Save audio file
      final audioFile = File('${directory.path}/$fileName');
      await audioFile.writeAsBytes(fileBytes);
      print("✅ Saved audio file locally: ${audioFile.path}");

      // Save metadata to Firestore (local collection)
      final firestore = FirebaseFirestore.instance;
      await firestore.collection('LocalPredictions').add({
        'file_name': fileName,
        'prediction': prediction,
        'confidence': confidence,
        'total_clips': totalClips,
        'male_clips': maleClips,
        'female_clips': femaleClips,
        'clip_results': clipResults.map((clip) => {
          'clip': clip['clip'],
          'prediction': clip['prediction'],
          'confidence': clip['confidence'],
        }).toList(),
        'local_path': audioFile.path,
        'created_at': FieldValue.serverTimestamp(),
      });
      
      print("✅ Saved metadata to Firestore");
    } catch (e) {
      print("❌ Error saving local file: $e");
      // Don't throw - allow the upload to continue even if local save fails
    }
  }

  // Safe parsing helpers
  double _parseDouble(dynamic value, double defaultValue) {
    if (value == null) return defaultValue;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  int _parseInt(dynamic value, int defaultValue) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  // UI Helper Methods
  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[700],
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green[700],
        behavior: SnackBarBehavior.floating,
      ),
    );
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
                    backgroundColor: serverReady ? Colors.green : Colors.orange,
                    radius: 6,
                  ),
                  label: Text(
                    serverReady ? 'Server Ready' : 'Server Warming Up',
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
                          onTap: (loading || !serverReady) ? null : _pickAndSendFile,
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
                                  child: Icon(
                                    Icons.cloud_upload_outlined,
                                    size: 80,
                                    color: (loading || !serverReady) 
                                        ? Colors.grey 
                                        : const Color(0xFFFFD54F),
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
                                  serverReady 
                                      ? 'Upload will save to Firebase and local storage'
                                      : 'Waiting for server to be ready...',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[400],
                                  ),
                                ),
                                const SizedBox(height: 24),
                                FilledButton.icon(
                                  onPressed: (loading || !serverReady) ? null : _pickAndSendFile,
                                  icon: const Icon(Icons.folder_open),
                                  label: Text(loading ? 'Processing...' : 'Browse Files'),
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
                              subtitle: 'Cloud + Local',
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
                              const Icon(
                                Icons.info_outline,
                                color: Color(0xFFFFD54F),
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
                                      'Files are analyzed and saved with prediction data',
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