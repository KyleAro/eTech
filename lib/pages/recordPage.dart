import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../style/mainpage_style.dart';
import '../widgets/stateless/recordtitle.dart';
import '../widgets/stateful/audioplayer.dart';
import '../widgets/stateful/audio_cleaner.dart';
import '../database/firebase_con.dart';
import '../database/firestore_con.dart';
import '../widgets/stateless/result_botsheet.dart';

class RecordPage extends StatefulWidget {
  @override
  _RecordPageState createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {
  final recorder = FlutterSoundRecorder();
  final TextEditingController titleController = TextEditingController();

  bool isRecorderReady = false;
  bool isRecording = false;
  bool isPredicting = false;

  String? rawAacPath;
  String? wavPath;

  // API Configuration
  static const String API_BASE_URL = "https://etech-rgsx.onrender.com";

  @override
  void initState() {
    super.initState();
    _initRecorder();
  }

  @override
  void dispose() {
    recorder.closeRecorder();
    titleController.dispose();
    super.dispose();
  }

  Future<void> _initRecorder() async {
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) throw 'Microphone permission not granted';
    await recorder.openRecorder();
    if (!mounted) return;
    setState(() => isRecorderReady = true);
    recorder.setSubscriptionDuration(const Duration(milliseconds: 500));
  }

  Future<String> _getFilePath() async {
    final dir = await getExternalStorageDirectory();
    int count = 1;
    String path = '';
    while (true) {
      path = '${dir!.path}/Undetermined_$count.aac';
      if (!await File(path).exists()) break;
      count++;
    }
    return path;
  }

  Future<void> startRecording() async {
    if (!isRecorderReady || isRecording) return;
    rawAacPath = await _getFilePath();
    titleController.text = rawAacPath!.split('/').last.split('.').first;

    await recorder.startRecorder(toFile: rawAacPath, codec: Codec.aacMP4);
    setState(() => isRecording = true);

    _showRecordingBottomSheet();
  }

  Future<void> stopRecording({bool discard = false}) async {
    if (!isRecorderReady || !isRecording) return;
    await recorder.stopRecorder();
    setState(() => isRecording = false);

    if (discard) {
      if (rawAacPath != null) await File(rawAacPath!).delete();
      if (wavPath != null) await File(wavPath!).delete();
      rawAacPath = null;
      wavPath = null;
      titleController.clear();
    }
  }

  Future<Map<String, dynamic>> _sendToMLServer(String filePath) async {
    print('🚀 DEBUG: Starting ML Server request');
    print('📂 DEBUG: File path: $filePath');
    
    final uri = Uri.parse("$API_BASE_URL/predict");
    print('🌐 DEBUG: API URL: $uri');
    
    final request = http.MultipartRequest("POST", uri);

    request.files.add(await http.MultipartFile.fromPath(
      "file",
      filePath,
      contentType: MediaType('audio', 'aac'),
    ));

    print('📤 DEBUG: Sending request to server...');
    
    final response = await request.send().timeout(
      const Duration(seconds: 90),
      onTimeout: () {
        print('⏰ DEBUG: Request timed out');
        throw TimeoutException('Server request timed out');
      },
    );
    
    print('📥 DEBUG: Response status code: ${response.statusCode}');
    
    final respStr = await response.stream.bytesToString();
    print('📋 DEBUG: Raw response string: $respStr');

    if (response.statusCode != 200) {
      print('❌ DEBUG: Server error - Status ${response.statusCode}');
      throw Exception("Server error: ${response.statusCode}");
    }

    final decoded = jsonDecode(respStr);
    print('🔍 DEBUG: Decoded JSON: $decoded');
    
    // Normalize prediction to Title Case
    String prediction = (decoded["final_prediction"] ?? "Unknown").toString().trim();
    print('🎯 DEBUG: Raw prediction: $prediction');
    
    if (prediction.toLowerCase() == 'male') {
      prediction = 'Male';
    } else if (prediction.toLowerCase() == 'female') {
      prediction = 'Female';
    }
    
    print('✅ DEBUG: Normalized prediction: $prediction');
    
    final result = {
      "status": decoded["status"] ?? "error",
      "prediction": prediction,
      "confidence": ((decoded["average_confidence"] ?? 0.0) as num).toDouble(),
      "total_clips": ((decoded["total_clips"] ?? 0) as num).toInt(),
      "male_clips": ((decoded["male_clips"] ?? 0) as num).toInt(),
      "female_clips": ((decoded["female_clips"] ?? 0) as num).toInt(),
      "prediction_summary": decoded["prediction_summary"] ?? [],
    };
    
    print('📦 DEBUG: Final result map: $result');
    return result;
  }

  // 1. Rename file locally based on prediction
  Future<String> _renameFileLocally(String oldPath, String prediction) async {
    print('📝 DEBUG: Renaming file locally');
    print('   Old path: $oldPath');
    print('   Prediction: $prediction');
    
    final file = File(oldPath);
    final dir = file.parent;
    
    final dateString = "${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}";
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    
    // Use editable title or default name
    String baseName = titleController.text.trim();
    if (baseName.isEmpty || baseName.startsWith('Undetermined')) {
      baseName = 'recording_${dateString}_$timestamp';
    }
    
    final newFileName = '${prediction}_$baseName.aac';
    final newPath = '${dir.path}/$newFileName';
    
    print('   New path: $newPath');
    
    await file.rename(newPath);
    print('✅ DEBUG: File renamed successfully');
    return newPath;
  }

  // 2. Upload to Firebase Storage
  Future<String> _uploadToFirebase(String filePath, String prediction) async {
    print('☁️ DEBUG: Uploading to Firebase');
    
    final firebaseConnect = FirebaseConnect();
    final file = File(filePath);
    final fileBytes = await file.readAsBytes();
    final fileName = filePath.split('/').last;
    
    print('   File name: $fileName');
    print('   File size: ${fileBytes.length} bytes');
    
    // Upload to gender-specific folder
    final downloadUrl = await firebaseConnect.uploadBytes(
      fileBytes,
      fileName,
      prediction,
    );
    
    print('✅ DEBUG: Upload complete. URL: $downloadUrl');
    return downloadUrl;
  }

  // 3. Save metadata to Firestore (LocalPredictions)
  Future<void> _saveToFirestore({
    required String fileName,
    required String prediction,
    required double confidence,
    required String downloadUrl,
    required String localPath,
    required int totalClips,
    required int maleClips,
    required int femaleClips,
    required List<dynamic> clipResults,
  }) async {
    print('💾 DEBUG: Saving to Firestore');
    
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
      'download_url': downloadUrl,
      'local_path': localPath,
      'created_at': FieldValue.serverTimestamp(),
    });
    
    print('✅ DEBUG: Firestore save complete');
  }

  // 4. Save to Undetermined collection (for recordings without prediction)
  Future<void> _saveUndeterminedToFirestore(String fileName, String filePath) async {
    print('💾 DEBUG: Saving to Undetermined collection');
    
    final firestore = FirebaseFirestore.instance;
    
    await firestore.collection('Undetermined').add({
      'file_name': fileName,
      'local_path': filePath,
      'timestamp': FieldValue.serverTimestamp(),
    });
    
    print('✅ DEBUG: Undetermined save complete');
  }

  // Complete workflow after prediction
  Future<void> _handlePredictionComplete({
    required BuildContext context,
    required Map<String, dynamic> predictionData,
    required bool autoSave,
  }) async {
    print('🎬 DEBUG: Starting handlePredictionComplete');
    print('   autoSave: $autoSave');
    print('   predictionData: $predictionData');
    
    try {
      String prediction = predictionData['prediction'];
      double confidence = predictionData['confidence'];
      int totalClips = predictionData['total_clips'];
      int maleClips = predictionData['male_clips'];
      int femaleClips = predictionData['female_clips'];
      List<dynamic> clipResults = predictionData['prediction_summary'];

      print('📊 DEBUG: Extracted data:');
      print('   Prediction: $prediction');
      print('   Confidence: $confidence');
      print('   Total clips: $totalClips');

      String? newPath;
      String? downloadUrl;
      Uint8List? fileBytes;

      if (autoSave && rawAacPath != null) {
        print('💾 DEBUG: Auto-save is enabled, starting save process...');
        
        // Show saving dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            content: Row(
              children: const [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text('Saving...'),
              ],
            ),
          ),
        );

        // 1. Rename file locally
        newPath = await _renameFileLocally(rawAacPath!, prediction);
        
        // 2. Upload to Firebase
        downloadUrl = await _uploadToFirebase(newPath, prediction);
        
        // 3. Save to Firestore (LocalPredictions)
        await _saveToFirestore(
          fileName: newPath.split('/').last,
          prediction: prediction,
          confidence: confidence,
          downloadUrl: downloadUrl,
          localPath: newPath,
          totalClips: totalClips,
          maleClips: maleClips,
          femaleClips: femaleClips,
          clipResults: clipResults,
        );

        // Read file bytes for result sheet
        fileBytes = await File(newPath).readAsBytes();

        Navigator.pop(context); // Close saving dialog
        print('✅ DEBUG: Save complete, dialog closed');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to $prediction folder'),
            backgroundColor: Colors.green[700],
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        print('📂 DEBUG: Not auto-saving, just getting file bytes');
        // Just get file bytes without saving
        if (rawAacPath != null) {
          fileBytes = await File(rawAacPath!).readAsBytes();
          print('   File bytes length: ${fileBytes?.length ?? 0}');
        }
      }

      print('🎉 DEBUG: Showing ResultBottomSheet');
      print('   Prediction: $prediction');
      print('   Confidence: $confidence');
      print('   Total clips: $totalClips');
      
      // Show result bottom sheet
      ResultBottomSheet.show(
        context,
        prediction: prediction,
        confidence: confidence,
        rawBytes: fileBytes,
        baseName: newPath?.split('/').last ?? titleController.text,
        totalClips: totalClips,
        maleClips: maleClips,
        femaleClips: femaleClips,
        clipResults: clipResults,
        showConfetti: true,
      );

      print('✅ DEBUG: ResultBottomSheet.show called successfully');

      // Clear paths after successful handling
      rawAacPath = null;
      wavPath = null;
      titleController.clear();
      
    } catch (e, stackTrace) {
      print('❌ DEBUG: Error in handlePredictionComplete: $e');
      print('📚 DEBUG: Stack trace: $stackTrace');
      
      Navigator.pop(context); // Close any loading dialog
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving: $e'),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // Save recording without prediction (as Undetermined)
  Future<void> _saveWithoutPrediction() async {
    if (rawAacPath == null) return;

    print('💾 DEBUG: Saving without prediction');

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          content: Row(
            children: const [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text('Saving...'),
            ],
          ),
        ),
      );

      final fileName = rawAacPath!.split('/').last;
      
      // Save to Undetermined collection
      await _saveUndeterminedToFirestore(fileName, rawAacPath!);

      Navigator.pop(context); // Close dialog

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved as Undetermined'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );

      // Clear paths
      rawAacPath = null;
      wavPath = null;
      titleController.clear();
      
    } catch (e) {
      print('❌ DEBUG: Error saving without prediction: $e');
      Navigator.pop(context);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showRecordingBottomSheet() {
    bool showExtraButtons = false;
    final audioPlayerService = AudioPlayerService();

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => WillPopScope(
        onWillPop: () async => !isPredicting,
        child: StatefulBuilder(builder: (context, setModalState) {
          return Theme(
            data: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.dark(
                primary: const Color(0xFFFFD54F),
                secondary: const Color(0xFFFFD54F),
                surface: const Color(0xFF1E1E1E),
                background: const Color(0xFF121212),
              ),
            ),
            child: Container(
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(top: 12, bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.grey[700],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [
                          // File name editor (show after recording)
                          if (showExtraButtons) ...[
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
                                      Icons.edit,
                                      color: const Color(0xFFFFD54F),
                                      size: 24,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextField(
                                        controller: titleController,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        decoration: InputDecoration(
                                          hintText: 'Edit file name (optional)',
                                          border: InputBorder.none,
                                          isDense: true,
                                          hintStyle: TextStyle(
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],

                          // Recording indicator
                          if (!showExtraButtons) ...[
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.red[900]?.withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: Colors.red[400],
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.red[400]!.withOpacity(0.5),
                                      blurRadius: 12,
                                      spreadRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Recording...',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],

                          // Timer display
                          StreamBuilder<RecordingDisposition>(
                            stream: recorder.onProgress,
                            builder: (context, snapshot) {
                              final duration = snapshot.hasData
                                  ? snapshot.data!.duration
                                  : Duration.zero;
                              final minutes = duration.inMinutes.toString().padLeft(2, '0');
                              final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
                              
                              return Card(
                                elevation: 4,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 40,
                                    vertical: 24,
                                  ),
                                  child: Text(
                                    '$minutes:$seconds',
                                    style: TextStyle(
                                      fontSize: 56,
                                      fontWeight: FontWeight.bold,
                                      color: showExtraButtons
                                          ? Colors.white
                                          : Colors.red[400],
                                      letterSpacing: 4,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 32),

                          // Stop button (when recording)
                          if (!showExtraButtons)
                            SizedBox(
                              width: 80,
                              height: 80,
                              child: FilledButton(
                                onPressed: () async {
                                  await stopRecording();
                                  try {
                                    wavPath = await AudioProcessor.convertToWav(rawAacPath!);
                                  } catch (_) {
                                    wavPath = rawAacPath;
                                  }
                                  setModalState(() => showExtraButtons = true);
                                },
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.red[400],
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  padding: EdgeInsets.zero,
                                ),
                                child: const Icon(
                                  Icons.stop,
                                  size: 36,
                                  color: Colors.white,
                                ),
                              ),
                            ),

                          // Audio player (after recording)
                          if (showExtraButtons && wavPath != null) ...[
                            Card(
                              elevation: 4,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: AudioPlayerControls(
                                  audioPlayer: audioPlayerService,
                                  filePath: wavPath!,
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],

                          // Action buttons (after recording)
                          if (showExtraButtons)
                            Column(
                              children: [
                                // Predict & Auto-Save button
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton.icon(
                                    onPressed: (rawAacPath == null || isPredicting)
                                        ? null
                                        : () async {
                                            print('🔘 DEBUG: Predict & Save button pressed');
                                            setState(() => isPredicting = true);
                                            
                                            try {
                                              print('📱 DEBUG: Closing recording bottom sheet');
                                              Navigator.pop(context); // Close recording sheet
                                              
                                              print('🔄 DEBUG: Calling _sendToMLServer');
                                              final predictionData = await _sendToMLServer(rawAacPath!);
                                              
                                              print('✅ DEBUG: Got prediction data, calling _handlePredictionComplete');
                                              await _handlePredictionComplete(
                                                context: context,
                                                predictionData: predictionData,
                                                autoSave: true, // Auto-save enabled
                                              );
                                              
                                              print('🎉 DEBUG: _handlePredictionComplete finished');
                                            } catch (e, stackTrace) {
                                              print('❌ DEBUG: Error in Predict & Save: $e');
                                              print('📚 DEBUG: Stack trace: $stackTrace');
                                              
                                              ResultBottomSheet.show(
                                                context,
                                                prediction: "Prediction failed: $e",
                                                confidence: 0.0,
                                                isError: true,
                                              );
                                            } finally {
                                              setState(() => isPredicting = false);
                                            }
                                          },
                                    icon: isPredicting
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(Icons.cloud_upload),
                                    label: Text(isPredicting ? 'Processing...' : 'Predict & Save'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.green[600],
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                
                                // Predict Only (no save)
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: (rawAacPath == null || isPredicting)
                                        ? null
                                        : () async {
                                            print('🔘 DEBUG: Predict Only button pressed');
                                            setState(() => isPredicting = true);
                                            
                                            try {
                                              print('📱 DEBUG: Closing recording bottom sheet');
                                              Navigator.pop(context);
                                              
                                              print('🔄 DEBUG: Calling _sendToMLServer');
                                              final predictionData = await _sendToMLServer(rawAacPath!);

                                              print('✅ DEBUG: Got prediction data, calling _handlePredictionComplete (no save)');
                                              await _handlePredictionComplete(
                                                context: context,
                                                predictionData: predictionData,
                                                autoSave: false, // No auto-save
                                              );
                                              
                                              print('🎉 DEBUG: _handlePredictionComplete finished');
                                            } catch (e, stackTrace) {
                                              print('❌ DEBUG: Error in Predict Only: $e');
                                              print('📚 DEBUG: Stack trace: $stackTrace');
                                              
                                              ResultBottomSheet.show(
                                                context,
                                                prediction: "Prediction failed: $e",
                                                confidence: 0.0,
                                                isError: true,
                                              );
                                            } finally {
                                              setState(() => isPredicting = false);
                                            }
                                          },
                                    icon: const Icon(Icons.psychology),
                                    label: const Text('Predict Only'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFFFFD54F),
                                      side: const BorderSide(color: Color(0xFFFFD54F)),
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                
                                // Save without prediction (Undetermined)
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: isPredicting
                                        ? null
                                        : () async {
                                            Navigator.pop(context);
                                            await _saveWithoutPrediction();
                                          },
                                    icon: const Icon(Icons.save_outlined),
                                    label: const Text('Save as Undetermined'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.grey[400],
                                      side: BorderSide(color: Colors.grey[700]!),
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                
                                // Discard button
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: isPredicting
                                        ? null
                                        : () async {
                                            await stopRecording(discard: true);
                                            Navigator.pop(context);
                                          },
                                    icon: const Icon(Icons.delete_outline),
                                    label: const Text('Discard Recording'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red[400],
                                      side: BorderSide(color: Colors.red[400]!),
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          body: Center(
            child: GestureDetector(
              onTap: () async {
                if (!isRecording) await startRecording();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 200,
                width: 200,
                child: NeuBox(
                  isPressed: isRecording,
                  child: Icon(isRecording ? Icons.stop : Icons.mic, size: 100, color: Colors.black),
                ),
              ),
            ),
          ),
        ),
        if (isPredicting)
          Positioned.fill(
            child: Container(
              color: Colors.black54,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 20),
                  Text("Predicting...", style: TextStyle(color: Colors.white, fontSize: 18)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}