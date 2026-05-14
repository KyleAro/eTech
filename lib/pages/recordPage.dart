import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
import 'result_botsheet.dart';
import 'package:etech/style/ripple_background.dart';

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

    final dateString =
        "${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}";
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

  // ===========================================================================
  // ADAPTER: turn the ML response map into a PredictionResult for the new sheet.
  // ===========================================================================
  PredictionResult _buildPredictionResult({
    required Map<String, dynamic> data,
    required Duration duration,
  }) {
    final summary = (data['prediction_summary'] as List?) ?? const [];
    final clips = <ClipPrediction>[];
    for (var i = 0; i < summary.length; i++) {
      final c = summary[i] as Map;
      clips.add(ClipPrediction(
        index: i + 1,
        gender: (c['prediction'] ?? 'unknown').toString(),
        confidence: ((c['confidence'] ?? 0.0) as num).toDouble(),
      ));
    }

    // Specimen number — derived from millis so it's stable per recording.
    // (Replace with your Firestore-counted number once you have it.)
    final specimen =
        (DateTime.now().millisecondsSinceEpoch % 1000); // 0..999

    return PredictionResult(
      gender: (data['prediction'] ?? 'unknown').toString(),
      confidence: (data['confidence'] as num?)?.toDouble() ?? 0.0,
      specimenNumber: specimen,
      recordedAt: DateTime.now(),
      duration: duration,
      clips: clips,
    );
  }

  // Complete workflow after prediction
  Future<void> _handlePredictionComplete({
    required BuildContext context,
    required Map<String, dynamic> predictionData,
    required bool autoSave,
    Duration? duration,
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

        // Show saving dialog (frosted style)
        _showSavingDialog();

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

        // Read file bytes (kept for future use, unused by new sheet API)
        fileBytes = await File(newPath).readAsBytes();

        Navigator.pop(context); // Close saving dialog
        print('✅ DEBUG: Save complete, dialog closed');

        _showFrostedSnack(
          'Filed under $prediction',
          accent: successGreen,
        );
      } else {
        print('📂 DEBUG: Not auto-saving, just getting file bytes');
        if (rawAacPath != null) {
          fileBytes = await File(rawAacPath!).readAsBytes();
          print('   File bytes length: ${fileBytes?.length ?? 0}');
        }
      }

      print('🎉 DEBUG: Showing result bottom sheet');

      // Bridge old kwargs → new PredictionResult API.
      final result = _buildPredictionResult(
        data: predictionData,
        duration: duration ?? Duration.zero,
      );

      await showResultBottomSheet(
        context,
        result: result,
      );

      print('✅ DEBUG: showResultBottomSheet returned');

      // Clear paths after successful handling
      rawAacPath = null;
      wavPath = null;
      titleController.clear();
    } catch (e, stackTrace) {
      print('❌ DEBUG: Error in handlePredictionComplete: $e');
      print('📚 DEBUG: Stack trace: $stackTrace');

      // Try to dismiss any loading dialog
      if (Navigator.canPop(context)) Navigator.pop(context);

      _showFrostedSnack('Error saving: $e', accent: recordRed);
    }
  }

  // Save recording without prediction (as Undetermined)
  Future<void> _saveWithoutPrediction() async {
    if (rawAacPath == null) return;

    print('💾 DEBUG: Saving without prediction');

    try {
      _showSavingDialog();

      final fileName = rawAacPath!.split('/').last;

      // Save to Undetermined collection
      await _saveUndeterminedToFirestore(fileName, rawAacPath!);

      Navigator.pop(context); // Close dialog

      _showFrostedSnack('Filed as Undetermined', accent: successGreen);

      // Clear paths
      rawAacPath = null;
      wavPath = null;
      titleController.clear();
    } catch (e) {
      print('❌ DEBUG: Error saving without prediction: $e');
      if (Navigator.canPop(context)) Navigator.pop(context);
      _showFrostedSnack('Error saving: $e', accent: recordRed);
    }
  }

  // ===========================================================================
  // SHARED UI HELPERS (frosted dialog + snackbar)
  // ===========================================================================

  void _showSavingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: textcolor.withValues(alpha: 0.25),
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: NeuBox(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: textcolor,
                ),
              ),
              const SizedBox(width: 14),
              Text(
                'Filing specimen…',
                style: GoogleFonts.quicksand(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: textcolor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFrostedSnack(String message, {required Color accent}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.quicksand(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: textcolor,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white.withValues(alpha: 0.95),
        elevation: 4,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: textcolor.withValues(alpha: 0.10),
            width: 0.5,
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // RECORDING BOTTOM SHEET
  // ===========================================================================

  void _showRecordingBottomSheet() {
    bool showExtraButtons = false;
    final audioPlayerService = AudioPlayerService();
    final sessionStart = DateTime.now();
    Duration capturedDuration = Duration.zero;

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: textcolor.withValues(alpha: 0.25),
      builder: (context) => WillPopScope(
        onWillPop: () async => !isPredicting,
        child: StatefulBuilder(builder: (context, setModalState) {
          final media = MediaQuery.of(context);
          return Container(
            height: media.size.height * 0.82,
            decoration: const BoxDecoration(
              gradient: pondGradient,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: RippleBackground(
                      centerAlignment: const Alignment(0, -0.4),
                    ),
                  ),
                  Column(
                    children: [
                      // Drag handle
                      Container(
                        width: 44,
                        height: 4,
                        margin: const EdgeInsets.only(top: 10, bottom: 14),
                        decoration: BoxDecoration(
                          color: textcolor.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),

                      // Title
                      Text(
                        showExtraButtons ? 'FIELD NOTE' : 'NOW LISTENING',
                        style: getCapsLabel(size: 11, opacity: 0.55),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        showExtraButtons ? 'Review' : 'Recording',
                        style: getSerifHeading(size: 28),
                      ),

                      const SizedBox(height: 18),

                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Column(
                            children: [
                              // File name editor (after recording)
                              if (showExtraButtons) ...[
                                NeuBox(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 4),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.edit_note_rounded,
                                        color:
                                            textcolor.withValues(alpha: 0.6),
                                        size: 22,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: TextField(
                                          controller: titleController,
                                          cursorColor: textcolor,
                                          style: GoogleFonts.quicksand(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: textcolor,
                                          ),
                                          decoration: InputDecoration(
                                            hintText: 'Specimen label',
                                            border: InputBorder.none,
                                            isDense: true,
                                            hintStyle: GoogleFonts.quicksand(
                                              color: textcolor
                                                  .withValues(alpha: 0.4),
                                              fontWeight: FontWeight.w400,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 18),
                              ],

                              // Live recording pulse
                              if (!showExtraButtons) ...[
                                _RecordingPulse(),
                                const SizedBox(height: 14),
                              ],

                              // Timer
                              StreamBuilder<RecordingDisposition>(
                                stream: recorder.onProgress,
                                builder: (context, snapshot) {
                                  final duration = snapshot.hasData
                                      ? snapshot.data!.duration
                                      : Duration.zero;
                                  if (isRecording) {
                                    capturedDuration = duration;
                                  }
                                  final minutes = duration.inMinutes
                                      .toString()
                                      .padLeft(2, '0');
                                  final seconds = (duration.inSeconds % 60)
                                      .toString()
                                      .padLeft(2, '0');

                                  return NeuBox(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 36,
                                      vertical: 20,
                                    ),
                                    child: Text(
                                      '$minutes:$seconds',
                                      style: GoogleFonts.quicksand(
                                        fontSize: 52,
                                        fontWeight: FontWeight.w300,
                                        color: showExtraButtons
                                            ? textcolor
                                            : recordRed,
                                        letterSpacing: 4,
                                        height: 1.0,
                                      ),
                                    ),
                                  );
                                },
                              ),

                              const SizedBox(height: 26),

                              // Stop button (while recording)
                              if (!showExtraButtons)
                                _StopButton(
                                  onTap: () async {
                                    await stopRecording();
                                    try {
                                      wavPath = await AudioProcessor
                                          .convertToWav(rawAacPath!);
                                    } catch (_) {
                                      wavPath = rawAacPath;
                                    }
                                    capturedDuration = DateTime.now()
                                        .difference(sessionStart);
                                    setModalState(
                                        () => showExtraButtons = true);
                                  },
                                ),

                              // Audio player (after recording)
                              if (showExtraButtons && wavPath != null) ...[
                                NeuBox(
                                  padding: const EdgeInsets.all(16),
                                  child: AudioPlayerControls(
                                    audioPlayer: audioPlayerService,
                                    filePath: wavPath!,
                                  ),
                                ),
                                const SizedBox(height: 18),
                              ],

                              // Action buttons (after recording)
                              if (showExtraButtons)
                                Column(
                                  children: [
                                    _PondButton.primary(
                                      label: isPredicting
                                          ? 'Processing…'
                                          : 'Identify & Archive',
                                      icon: isPredicting
                                          ? null
                                          : Icons.auto_awesome_rounded,
                                      busy: isPredicting,
                                      onTap: (rawAacPath == null ||
                                              isPredicting)
                                          ? null
                                          : () async {
                                              print(
                                                  '🔘 DEBUG: Predict & Save button pressed');
                                              setState(
                                                  () => isPredicting = true);
                                              try {
                                                print(
                                                    '📱 DEBUG: Closing recording bottom sheet');
                                                Navigator.pop(context);

                                                print(
                                                    '🔄 DEBUG: Calling _sendToMLServer');
                                                final predictionData =
                                                    await _sendToMLServer(
                                                        rawAacPath!);

                                                print(
                                                    '✅ DEBUG: Got prediction data, calling _handlePredictionComplete');
                                                await _handlePredictionComplete(
                                                  context: context,
                                                  predictionData:
                                                      predictionData,
                                                  autoSave: true,
                                                  duration: capturedDuration,
                                                );

                                                print(
                                                    '🎉 DEBUG: _handlePredictionComplete finished');
                                              } catch (e, stackTrace) {
                                                print(
                                                    '❌ DEBUG: Error in Predict & Save: $e');
                                                print(
                                                    '📚 DEBUG: Stack trace: $stackTrace');
                                                _showFrostedSnack(
                                                    'Prediction failed: $e',
                                                    accent: recordRed);
                                              } finally {
                                                setState(() =>
                                                    isPredicting = false);
                                              }
                                            },
                                    ),
                                    const SizedBox(height: 10),
                                    _PondButton.secondary(
                                      label: 'Identify Only',
                                      icon: Icons.psychology_outlined,
                                      onTap: (rawAacPath == null ||
                                              isPredicting)
                                          ? null
                                          : () async {
                                              print(
                                                  '🔘 DEBUG: Predict Only button pressed');
                                              setState(
                                                  () => isPredicting = true);
                                              try {
                                                print(
                                                    '📱 DEBUG: Closing recording bottom sheet');
                                                Navigator.pop(context);

                                                print(
                                                    '🔄 DEBUG: Calling _sendToMLServer');
                                                final predictionData =
                                                    await _sendToMLServer(
                                                        rawAacPath!);

                                                print(
                                                    '✅ DEBUG: Got prediction data, calling _handlePredictionComplete (no save)');
                                                await _handlePredictionComplete(
                                                  context: context,
                                                  predictionData:
                                                      predictionData,
                                                  autoSave: false,
                                                  duration: capturedDuration,
                                                );

                                                print(
                                                    '🎉 DEBUG: _handlePredictionComplete finished');
                                              } catch (e, stackTrace) {
                                                print(
                                                    '❌ DEBUG: Error in Predict Only: $e');
                                                print(
                                                    '📚 DEBUG: Stack trace: $stackTrace');
                                                _showFrostedSnack(
                                                    'Prediction failed: $e',
                                                    accent: recordRed);
                                              } finally {
                                                setState(() =>
                                                    isPredicting = false);
                                              }
                                            },
                                    ),
                                    const SizedBox(height: 10),
                                    _PondButton.ghost(
                                      label: 'File as Undetermined',
                                      icon: Icons.bookmark_outline_rounded,
                                      onTap: isPredicting
                                          ? null
                                          : () async {
                                              Navigator.pop(context);
                                              await _saveWithoutPrediction();
                                            },
                                    ),
                                    const SizedBox(height: 10),
                                    _PondButton.danger(
                                      label: 'Discard',
                                      icon: Icons.delete_outline_rounded,
                                      onTap: isPredicting
                                          ? null
                                          : () async {
                                              await stopRecording(
                                                  discard: true);
                                              Navigator.pop(context);
                                            },
                                    ),
                                    const SizedBox(height: 18),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  // ===========================================================================
  // MAIN PAGE — field station landing
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: Colors.transparent,
          body: Container(
            decoration: const BoxDecoration(gradient: pondGradient),
            child: Stack(
              children: [
                const Positioned.fill(child: RippleBackground()),
                SafeArea(
                  child: Column(
                    children: [
                      const SizedBox(height: 24),
                      // Header
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          children: [
                            Text(
                              'FIELD STATION',
                              style:
                                  getCapsLabel(size: 11, opacity: 0.55),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Tap to listen',
                              style: getSerifHeading(size: 32),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Capture a duckling and we’ll log it to the journal.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.quicksand(
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                color: textcolor.withValues(alpha: 0.65),
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const Spacer(),

                      // Big record button
                      _RecordButton(
                        isRecording: isRecording,
                        onTap: () async {
                          if (!isRecording) await startRecording();
                        },
                      ),

                      const SizedBox(height: 18),
                      Text(
                        isRecorderReady
                            ? 'Mic ready'
                            : 'Waiting for permission…',
                        style: getCapsLabel(size: 10, opacity: 0.5),
                      ),

                      const Spacer(flex: 2),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (isPredicting)
          Positioned.fill(
            child: Container(
              color: textcolor.withValues(alpha: 0.35),
              child: Center(
                child: NeuBox(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 26, vertical: 22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: textcolor,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Identifying…',
                        style: GoogleFonts.quicksand(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: textcolor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// =============================================================================
// PRIVATE WIDGETS — kept in this file so the import surface doesn't grow
// =============================================================================

/// Big circular record button — duckling-yellow when idle, red when recording.
class _RecordButton extends StatelessWidget {
  final bool isRecording;
  final VoidCallback onTap;
  const _RecordButton({required this.isRecording, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fill = isRecording ? recordRed : secondColor;
    final glow = isRecording ? recordRed : ducklingYellowDark;
    final iconColor = isRecording ? Colors.white : textcolor;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        width: 184,
        height: 184,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fill,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.7),
            width: 4,
          ),
          boxShadow: [
            BoxShadow(
              color: glow.withValues(alpha: 0.45),
              blurRadius: 36,
              spreadRadius: 4,
            ),
            BoxShadow(
              color: textcolor.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Icon(
          isRecording ? Icons.stop_rounded : Icons.mic_rounded,
          size: 80,
          color: iconColor,
        ),
      ),
    );
  }
}

/// Pulsing red dot for active recording state.
class _RecordingPulse extends StatefulWidget {
  @override
  State<_RecordingPulse> createState() => _RecordingPulseState();
}

class _RecordingPulseState extends State<_RecordingPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = _c.value;
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: recordRed.withValues(alpha: 0.10 + 0.10 * t),
          ),
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: recordRed,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: recordRed.withValues(alpha: 0.55),
                  blurRadius: 10 + 8 * t,
                  spreadRadius: 2 + 3 * t,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Square stop button inside the recording sheet.
class _StopButton extends StatelessWidget {
  final VoidCallback onTap;
  const _StopButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          color: recordRed,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: recordRed.withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Icon(
          Icons.stop_rounded,
          size: 36,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Reusable pond-themed button with primary / secondary / ghost / danger variants.
class _PondButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color background;
  final Color foreground;
  final Color borderColor;
  final bool filled;
  final bool busy;

  const _PondButton._({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.background,
    required this.foreground,
    required this.borderColor,
    required this.filled,
    this.busy = false,
  });

  factory _PondButton.primary({
    required String label,
    IconData? icon,
    VoidCallback? onTap,
    bool busy = false,
  }) =>
      _PondButton._(
        label: label,
        icon: icon,
        onTap: onTap,
        background: textcolor,
        foreground: Colors.white,
        borderColor: Colors.transparent,
        filled: true,
        busy: busy,
      );

  factory _PondButton.secondary({
    required String label,
    IconData? icon,
    VoidCallback? onTap,
  }) =>
      _PondButton._(
        label: label,
        icon: icon,
        onTap: onTap,
        background: secondColor,
        foreground: textcolor,
        borderColor: Colors.transparent,
        filled: true,
      );

  factory _PondButton.ghost({
    required String label,
    IconData? icon,
    VoidCallback? onTap,
  }) =>
      _PondButton._(
        label: label,
        icon: icon,
        onTap: onTap,
        background: Colors.white.withValues(alpha: 0.5),
        foreground: textcolor,
        borderColor: textcolor.withValues(alpha: 0.15),
        filled: false,
      );

  factory _PondButton.danger({
    required String label,
    IconData? icon,
    VoidCallback? onTap,
  }) =>
      _PondButton._(
        label: label,
        icon: icon,
        onTap: onTap,
        background: Colors.white.withValues(alpha: 0.4),
        foreground: recordRed,
        borderColor: recordRed.withValues(alpha: 0.4),
        filled: false,
      );

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Opacity(
      opacity: disabled ? 0.5 : 1.0,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 0.5),
            boxShadow: filled
                ? [
                    BoxShadow(
                      color: background == textcolor
                          ? textcolor.withValues(alpha: 0.25)
                          : background.withValues(alpha: 0.30),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: foreground,
                  ),
                )
              else if (icon != null)
                Icon(icon, size: 18, color: foreground),
              if (busy || icon != null) const SizedBox(width: 10),
              Text(
                label,
                style: GoogleFonts.quicksand(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: foreground,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}