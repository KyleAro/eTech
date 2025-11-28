import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../database/firebase_con.dart';
import '../database/firestore_con.dart';
import '../widgets/stateless/loading_screen.dart';
import '../widgets/stateless/result_botsheet.dart';

// === COLOR CONSTANTS ===
const Color backgroundColor = Color(0xFF121212);
const Color secondColor = Color(0xFF1E1E1E);
const Color textcolor = Color(0xFFFFFFFF);
const Color accentColor = Color(0xFFFFD54F);

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
  String serverMessage = 'Checking server...';

  final FirebaseConnect _storageService = FirebaseConnect();
  final FirestoreConnect _firestoreService = FirestoreConnect();

  // API Configuration
  static const String API_BASE_URL = "https://etech-rgsx.onrender.com";
  static const Duration REQUEST_TIMEOUT = Duration(seconds: 90);
  static const int MAX_FILE_SIZE = 10 * 1024 * 1024; // 10MB
  static const int MAX_RETRIES = 3;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeApp();
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

  Future<void> _initializeApp() async {
    await wakeUpServer();
    await _checkAndRequestPermissions();
  }

  // === PERMISSION HANDLING ===
  Future<bool> _checkAndRequestPermissions() async {
    if (Platform.isAndroid) {
      // Check Android version
      final androidInfo = await _getAndroidVersion();
      
      if (androidInfo >= 13) {
        // Android 13+ uses granular media permissions
        final status = await Permission.audio.request();
        if (!status.isGranted) {
          _showPermissionDialog();
          return false;
        }
      } else {
        // Android 12 and below
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          _showPermissionDialog();
          return false;
        }
      }
    }
    return true;
  }

  Future<int> _getAndroidVersion() async {
    // Simplified - you might want to use device_info_plus package
    return 13; // Default to 13+ for safety
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permission Required'),
        content: const Text(
          'This app needs storage permission to access audio files. '
          'Please grant the permission in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  // === SERVER STATUS ===
  Future<void> wakeUpServer() async {
    try {
      var response = await http
          .get(Uri.parse("$API_BASE_URL/status"))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        var data = json.decode(response.body);
        bool isReady = data['status'] == 'ready';

        if (mounted) {
          setState(() {
            serverReady = isReady;
            serverMessage = isReady ? 'Server Ready' : 'Server Warming Up...';
          });
        }

        if (isReady) {
          print("✅ Server active and ready");
        } else {
          print("⚠️ Server warming up...");
        }
      } else {
        if (mounted) {
          setState(() {
            serverReady = false;
            serverMessage = 'Server Error (${response.statusCode})';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          serverReady = false;
          serverMessage = 'Server Offline';
        });
      }
      print("❌ Server unreachable: $e");
    }
  }

  // === FILE VALIDATION ===
  Future<bool> _validateAudioFile(File file) async {
    // Check extension
    final extension = file.path.split('.').last.toLowerCase();
    final validExtensions = ['mp3', 'wav', 'aac', 'm4a', 'ogg', 'flac'];

    if (!validExtensions.contains(extension)) {
      _showErrorDialog(
        'Invalid Format',
        'Please select an audio file.\nSupported: ${validExtensions.join(", ")}',
      );
      return false;
    }

    // Check file size
    final fileSize = await file.length();

    if (fileSize == 0) {
      _showErrorDialog('Empty File', 'The selected file is empty.');
      return false;
    }

    if (fileSize > MAX_FILE_SIZE) {
      final sizeMB = (fileSize / 1024 / 1024).toStringAsFixed(1);
      _showErrorDialog(
        'File Too Large',
        'File must be under 10MB.\nYour file: ${sizeMB}MB',
      );
      return false;
    }

    return true;
  }

  // === MAIN UPLOAD FLOW ===
  Future<void> _pickAndSendFile() async {
    // Check permissions first
    if (!await _checkAndRequestPermissions()) {
      return;
    }

    // Check server status
    if (!serverReady) {
      _showWarningSnackBar('Server is warming up. Please wait...');
      return;
    }

    // Pick file
    FilePickerResult? resultPicker =
        await FilePicker.platform.pickFiles(type: FileType.audio);

    if (resultPicker == null) return;

    File? file;
    final pickedFile = resultPicker.files.single;

    // Handle file path
    if (pickedFile.path != null) {
      file = File(pickedFile.path!);
    } else if (pickedFile.bytes != null) {
      final dir = await getTemporaryDirectory();
      final tempFile = File('${dir.path}/${pickedFile.name}');
      await tempFile.writeAsBytes(pickedFile.bytes!);
      file = tempFile;
    } else {
      _showErrorDialog('Invalid File', 'Could not read the selected file.');
      return;
    }

    // Validate file
    if (!await _validateAudioFile(file)) {
      return;
    }

    setState(() => loading = true);

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const LoadingScreen(
        animationAsset: 'assets/anim/loading2.json',
        message: "Analyzing audio...\nThis may take up to 90 seconds",
        backgroundColor: secondColor,
        textColor: textcolor,
      ),
    );

    try {
      // Upload with retry logic
      final response = await _uploadWithRetry(file);

      if (response.statusCode == 200) {
        await _handleSuccessResponse(response.body, file, pickedFile.name);
      } else if (response.statusCode == 503) {
        Navigator.pop(context);
        _showErrorDialog(
          'Server Busy',
          'The server is still warming up.\nPlease try again in 30 seconds.',
        );
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
      Navigator.pop(context);
      _showErrorDialog(
        'Request Timeout',
        'The request took too long.\nTry a shorter audio file.',
      );
      print("⏱️ Timeout: $e");
    } on SocketException catch (e) {
      Navigator.pop(context);
      _showErrorDialog(
        'Network Error',
        'Please check your internet connection.',
      );
      print("🌐 Network Error: $e");
    } catch (e) {
      Navigator.pop(context);
      _showErrorDialog('Upload Failed', _getReadableErrorMessage(e));
      print("❌ Error: $e");
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  // === UPLOAD WITH RETRY ===
  Future<http.Response> _uploadWithRetry(File file) async {
    int attempts = 0;

    while (attempts < MAX_RETRIES) {
      attempts++;
      print("📡 Upload attempt $attempts/$MAX_RETRIES");

      try {
        var request = http.MultipartRequest(
          'POST',
          Uri.parse("$API_BASE_URL/predict"),
        );

        request.files.add(await http.MultipartFile.fromPath('file', file.path));

        var streamedResponse = await request.send().timeout(
          REQUEST_TIMEOUT,
          onTimeout: () {
            throw TimeoutException('Upload timed out after ${REQUEST_TIMEOUT.inSeconds}s');
          },
        );

        var response = await http.Response.fromStream(streamedResponse);

        print("📡 Response Status: ${response.statusCode}");

        if (response.statusCode == 200) {
          return response;
        } else if (response.statusCode == 503 && attempts < MAX_RETRIES) {
          print("⏳ Server busy, retrying in 10 seconds...");
          await Future.delayed(const Duration(seconds: 10));
          continue;
        } else {
          return response;
        }
      } catch (e) {
        if (attempts >= MAX_RETRIES) {
          rethrow;
        }
        print("⚠️ Attempt $attempts failed: $e");
        await Future.delayed(Duration(seconds: 5 * attempts));
      }
    }

    throw Exception('Max retries exceeded');
  }

  // === HANDLE SUCCESS RESPONSE ===
  Future<void> _handleSuccessResponse(
    String responseBody,
    File file,
    String originalFileName,
  ) async {
    try {
      var data = json.decode(responseBody);

      // Check for error in response
      if (data['status'] == 'error') {
        Navigator.pop(context);
        _showErrorDialog('Prediction Error', data['message'] ?? 'Unknown error');
        return;
      }

      // Parse prediction
      String prediction = _normalizePrediction(data['final_prediction']);

      if (prediction == 'Unknown') {
        Navigator.pop(context);
        _showErrorDialog('Invalid Prediction', 'Server returned unexpected prediction value');
        return;
      }

      // Parse numeric values
      double confidence = _parseDouble(data['average_confidence'], 0.0);
      int totalClips = _parseInt(data['total_clips'], 0);
      int maleClips = _parseInt(data['male_clips'], 0);
      int femaleClips = _parseInt(data['female_clips'], 0);
      List<dynamic> clipResults = data['prediction_summary'] ?? [];

      print("✅ Parsed Results:");
      print("   Prediction: $prediction");
      print("   Confidence: $confidence%");
      print("   Total Clips: $totalClips (M:$maleClips, F:$femaleClips)");

      // Generate filename
      final newFileName = _generateFileName(prediction, originalFileName);

      // Read file bytes
      final fileBytes = await file.readAsBytes();

      // Save locally
      await _saveLocalFile(
        fileBytes,
        newFileName,
        prediction,
        confidence,
        totalClips,
        maleClips,
        femaleClips,
        clipResults,
      );

      // Upload to Firebase
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

      // Log analytics
      await _logPrediction(prediction, confidence, totalClips);

      Navigator.pop(context); // Close loading

      // Show success
      _showSuccessSnackBar('✅ Saved to $prediction folder');

      // Show results
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
      _showErrorDialog('Parse Error', 'Failed to process server response');
    }
  }

  // === SAVE LOCAL FILE ===
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
      final directory = await getExternalStorageDirectory();
      if (directory == null) {
        print("⚠️ External storage not available");
        return;
      }

      // Create gender-specific folder
      final genderFolder = Directory('${directory.path}/$prediction');
      if (!await genderFolder.exists()) {
        await genderFolder.create(recursive: true);
      }

      // Save audio file
      final audioFile = File('${genderFolder.path}/$fileName');
      await audioFile.writeAsBytes(fileBytes);
      print("✅ Saved audio: ${audioFile.path}");

      // Save metadata JSON
      final metadataFile = File('${genderFolder.path}/${fileName}.json');
      final metadata = {
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
        'created_at': DateTime.now().toIso8601String(),
        'audio_path': audioFile.path,
      };

      await metadataFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(metadata),
      );
      print("✅ Saved metadata: ${metadataFile.path}");

      // Save to Firestore (local collection)
      await FirebaseFirestore.instance.collection('LocalPredictions').add({
        ...metadata,
        'local_path': audioFile.path,
        'created_at': FieldValue.serverTimestamp(),
      });

      print("✅ Saved to Firestore");
    } catch (e) {
      print("❌ Error saving local file: $e");
      // Don't throw - allow upload to continue
    }
  }

  // === ANALYTICS LOGGING ===
  Future<void> _logPrediction(String prediction, double confidence, int totalClips) async {
    try {
      await FirebaseFirestore.instance.collection('PredictionStats').add({
        'prediction': prediction,
        'confidence': confidence,
        'total_clips': totalClips,
        'timestamp': FieldValue.serverTimestamp(),
        'device_info': {
          'platform': Platform.operatingSystem,
          'version': Platform.operatingSystemVersion,
        },
      });
    } catch (e) {
      print("⚠️ Failed to log prediction: $e");
    }
  }

  // === HELPER METHODS ===
  String _generateFileName(String prediction, String originalFileName) {
    final dateString = DateTime.now().toIso8601String().split('T')[0];
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final originalName = originalFileName.split('.').first
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(' ', '_');
    return "${prediction}_${originalName}_${dateString}_$timestamp.wav";
  }

  String _normalizePrediction(dynamic pred) {
    if (pred == null) return 'Unknown';
    final predLower = pred.toString().toLowerCase().trim();
    if (predLower == 'male') return 'Male';
    if (predLower == 'female') return 'Female';
    return 'Unknown';
  }

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

  String _getReadableErrorMessage(dynamic error) {
    final errorStr = error.toString();
    if (error is SocketException) {
      return 'No internet connection.\nPlease check your network.';
    } else if (error is TimeoutException) {
      return 'Request timed out.\nTry a shorter audio file.';
    } else if (error is FormatException) {
      return 'Invalid server response.\nPlease try again.';
    } else if (errorStr.contains('HandshakeException')) {
      return 'SSL connection failed.\nCheck your security settings.';
    } else {
      return 'Unexpected error:\n${error.toString()}';
    }
  }

  // === UI HELPERS ===
  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: secondColor,
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(backgroundColor: accentColor),
            child: const Text('OK', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red[700],
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green[700],
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showWarningSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.orange[700],
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // === BUILD UI ===
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.dark(
          primary: accentColor,
          secondary: accentColor,
          surface: secondColor,
          background: backgroundColor,
        ),
      ),
      home: Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          backgroundColor: secondColor,
          elevation: 0,
          title: const Text(
            'Gender Prediction',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 20),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: wakeUpServer,
              tooltip: 'Refresh Server Status',
            ),
          ],
        ),
        body: Column(
          children: [
            // Server Status Banner
            _buildServerStatusBanner(),

            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Main Upload Card
                      _buildUploadCard(),

                      const SizedBox(height: 32),

                      // Info Cards Row
                      Row(
                        children: [
                          Expanded(
                            child: _buildInfoCard(
                              icon: Icons.audiotrack,
                              title: 'Formats',
                              subtitle: 'MP3, WAV, AAC\nM4A, OGG, FLAC',
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildInfoCard(
                              icon: Icons.cloud_done,
                              title: 'Auto Save',
                              subtitle: 'Cloud + Local\nStorage',
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Additional Info Card
                      _buildAutomaticProcessingCard(),
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

  Widget _buildServerStatusBanner() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: serverReady ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
        border: Border(
          bottom: BorderSide(
            color: serverReady ? Colors.green.withOpacity(0.3) : Colors.orange.withOpacity(0.3),
            width: 2,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: serverReady ? Colors.green : Colors.orange,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (serverReady ? Colors.green : Colors.orange).withOpacity(0.5),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            serverMessage,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: serverReady ? Colors.green[300] : Colors.orange[300],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadCard() {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
                  color: accentColor.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.cloud_upload_outlined,
                  size: 80,
                  color: (loading || !serverReady) ? Colors.grey : accentColor,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Select Audio File',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                serverReady
                    ? 'Upload will save to Firebase and local storage'
                    : 'Waiting for server to be ready...',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[400]),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: (loading || !serverReady) ? null : _pickAndSendFile,
                icon: const Icon(Icons.folder_open),
                label: Text(loading ? 'Processing...' : 'Browse Files'),
                style: FilledButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
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
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(icon, size: 36, color: accentColor),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(fontSize: 12, color: Colors.grey[400]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAutomaticProcessingCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: accentColor, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Automatic Processing',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Wait until the status above shows "Server Ready" before uploading. ',
                    style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}