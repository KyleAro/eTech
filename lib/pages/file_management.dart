import 'package:etech/pages/MainPage.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:io';
import '../widgets/stateful/audioplayer.dart';
import 'package:etech/style/mainpage_style.dart';
import '../widgets/stateless/loading_screen.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:etech/style/ripple_background.dart';

// Model to hold file + metadata
class AudioFileWithMetadata {
  final FileSystemEntity file;
  final String prediction;
  final double confidence;
  final int totalClips;
  final int maleClips;
  final int femaleClips;
  final List<dynamic> clipResults;
  final DateTime createdAt;

  AudioFileWithMetadata({
    required this.file,
    required this.prediction,
    required this.confidence,
    required this.totalClips,
    required this.maleClips,
    required this.femaleClips,
    required this.clipResults,
    required this.createdAt,
  });
}

class FileManagement extends StatefulWidget {
  final String? initialFilter;

  const FileManagement({Key? key, this.initialFilter}) : super(key: key);

  @override
  _FileManagementState createState() => _FileManagementState();
}

class _FileManagementState extends State<FileManagement> {
  List<AudioFileWithMetadata> audioFiles = [];
  bool isLoading = true;
  int? expandedIndex;
  late final AudioPlayerService audioPlayer;
  late String filterGender; // 'All', 'Male', 'Female', 'Undetermined'

  @override
  void initState() {
    super.initState();
    audioPlayer = AudioPlayerService();
    filterGender = widget.initialFilter ?? 'All';
    loadAudioFiles();
  }

  @override
  void dispose() {
    audioPlayer.dispose();
    super.dispose();
  }

  Future<void> loadAudioFiles() async {
    setState(() => isLoading = true);

    if (Platform.isAndroid) {
      await [Permission.storage, Permission.manageExternalStorage].request();
    }

    final directory = await getExternalStorageDirectory();
    if (directory != null) {
      try {
        final files = await Directory(directory.path)
            .list()
            .where((file) =>
                file.path.toLowerCase().endsWith(".wav") ||
                file.path.toLowerCase().endsWith(".aac") ||
                file.path.toLowerCase().endsWith(".mp3") ||
                file.path.toLowerCase().endsWith(".m4a"))
            .toList();

        final firestore = FirebaseFirestore.instance;
        List<AudioFileWithMetadata> filesWithMeta = [];

        for (var file in files) {
          final fileName = file.uri.pathSegments.last;

          final querySnapshot = await firestore
              .collection('LocalPredictions')
              .where('file_name', isEqualTo: fileName)
              .limit(1)
              .get();

          if (querySnapshot.docs.isNotEmpty) {
            final doc = querySnapshot.docs.first;
            final data = doc.data();

            filesWithMeta.add(AudioFileWithMetadata(
              file: file,
              prediction: data['prediction'] ?? 'Unknown',
              confidence: (data['confidence'] ?? 0.0).toDouble(),
              totalClips: data['total_clips'] ?? 0,
              maleClips: data['male_clips'] ?? 0,
              femaleClips: data['female_clips'] ?? 0,
              clipResults: data['clip_results'] ?? [],
              createdAt:
                  (data['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
            ));
          } else if (fileName.contains('Undetermined')) {
            final querySnapshot2 = await firestore
                .collection('Undetermined')
                .where('file_name', isEqualTo: fileName)
                .limit(1)
                .get();

            filesWithMeta.add(AudioFileWithMetadata(
              file: file,
              prediction: 'Undetermined',
              confidence: 0.0,
              totalClips: 0,
              maleClips: 0,
              femaleClips: 0,
              clipResults: [],
              createdAt: querySnapshot2.docs.isNotEmpty
                  ? (querySnapshot2.docs.first.data()['timestamp'] as Timestamp?)
                          ?.toDate() ??
                      DateTime.now()
                  : DateTime.now(),
            ));
          }
        }

        filesWithMeta.sort((a, b) => b.createdAt.compareTo(a.createdAt));

        setState(() {
          audioFiles = filesWithMeta;
          isLoading = false;
        });
      } catch (e) {
        print("⚠️ Error reading files: $e");
        setState(() => isLoading = false);
      }
    }
  }

  List<AudioFileWithMetadata> get filteredFiles {
    if (filterGender == 'All') return audioFiles;
    return audioFiles.where((f) => f.prediction == filterGender).toList();
  }

  Future<void> deleteAllRecordings() async {
    final confirm = await _showPondConfirm(
      title: 'Empty the archive?',
      message: filterGender == 'All'
          ? 'This will delete every specimen in the journal. This cannot be undone.'
          : 'This will delete every $filterGender specimen. This cannot be undone.',
      confirmLabel: 'Delete All',
      destructive: true,
    );

    if (confirm != true) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: textcolor.withValues(alpha: 0.25),
      builder: (_) => const LoadingScreen(message: "Clearing the archive…"),
    );

    final firestore = FirebaseFirestore.instance;
    final storage = FirebaseStorage.instance;
    final filesToDelete = filteredFiles;

    try {
      for (var fileData in filesToDelete) {
        final localFile = File(fileData.file.path);
        if (await localFile.exists()) await localFile.delete();

        final fileName = fileData.file.uri.pathSegments.last;

        final storagePath = fileData.prediction == 'Undetermined'
            ? 'Undetermined Ducklings/$fileName'
            : '${fileData.prediction} Ducklings/$fileName';

        try {
          await storage.ref().child(storagePath).delete();
        } on FirebaseException catch (e) {
          if (e.code != 'object-not-found') {
            print("❌ Firebase Storage deletion error: $e");
          }
        }

        final collection = fileData.prediction == 'Undetermined'
            ? 'Undetermined'
            : 'LocalPredictions';

        final snapshot = await firestore
            .collection(collection)
            .where('file_name', isEqualTo: fileName)
            .get();

        for (var doc in snapshot.docs) {
          await doc.reference.delete();
        }
      }

      await loadAudioFiles();

      _showPondSnack(
        filterGender == 'All'
            ? 'Archive cleared'
            : 'All $filterGender specimens removed',
        accent: successGreen,
      );
    } catch (e) {
      _showPondSnack('Failed to delete files: $e', accent: recordRed);
    } finally {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
    }
  }

  Future<void> deleteAudio(AudioFileWithMetadata fileData, int index) async {
    final fileName = fileData.file.uri.pathSegments.last;
    final confirm = await _showPondConfirm(
      title: 'Remove specimen?',
      message: '"$fileName" will be deleted from the archive.',
      confirmLabel: 'Delete',
      destructive: true,
    );

    if (confirm != true) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: textcolor.withValues(alpha: 0.25),
      builder: (_) => const LoadingScreen(message: "Removing specimen…"),
    );

    final firestore = FirebaseFirestore.instance;
    final storage = FirebaseStorage.instance;

    try {
      final storagePath = fileData.prediction == 'Undetermined'
          ? 'Undetermined Ducklings/$fileName'
          : '${fileData.prediction} Ducklings/$fileName';

      try {
        await storage.ref().child(storagePath).delete();
      } on FirebaseException catch (e) {
        if (e.code != 'object-not-found') {
          print("❌ Firebase Storage deletion error: $e");
        }
      }

      final collection = fileData.prediction == 'Undetermined'
          ? 'Undetermined'
          : 'LocalPredictions';

      final snapshot = await firestore
          .collection(collection)
          .where('file_name', isEqualTo: fileName)
          .get();

      for (var doc in snapshot.docs) {
        await doc.reference.delete();
      }

      final fileToDelete = File(fileData.file.path);
      if (await fileToDelete.exists()) {
        await fileToDelete.delete();
      }

      await loadAudioFiles();

      _showPondSnack('Removed $fileName', accent: successGreen);
    } catch (e) {
      _showPondSnack('Failed to delete file: $e', accent: recordRed);
    } finally {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
    }
  }

  // ===========================================================================
  // POND-STYLE DIALOGS & SNACKBARS
  // ===========================================================================

  Future<bool?> _showPondConfirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      barrierColor: textcolor.withValues(alpha: 0.25),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: NeuBox(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: getSerifHeading(size: 22)),
              const SizedBox(height: 8),
              Text(
                message,
                style: GoogleFonts.quicksand(
                  fontSize: 13,
                  color: textcolor.withValues(alpha: 0.7),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.quicksand(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: textcolor.withValues(alpha: 0.65),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => Navigator.pop(context, true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: destructive ? recordRed : textcolor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        confirmLabel,
                        style: GoogleFonts.quicksand(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPondSnack(String message, {required Color accent}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
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
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final displayFiles = filteredFiles;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'ARCHIVE',
          style: getCapsLabel(size: 12, opacity: 0.7),
        ),
        centerTitle: true,
        iconTheme: IconThemeData(color: textcolor),
        actions: [
          if (displayFiles.isNotEmpty)
            IconButton(
              icon: Icon(Icons.delete_sweep_rounded, color: textcolor),
              onPressed: deleteAllRecordings,
              tooltip: 'Empty the archive',
            ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: pondGradient),
        child: Stack(
          children: [
            const Positioned.fill(child: RippleBackground()),
            SafeArea(
              child: Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Field Journal',
                          style: getSerifHeading(size: 30),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${audioFiles.length} ${audioFiles.length == 1 ? 'specimen' : 'specimens'} collected',
                          style: GoogleFonts.quicksand(
                            fontSize: 12,
                            color: textcolor.withValues(alpha: 0.6),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Filter chips
                  SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      children: [
                        _buildFilterChip('All', audioFiles.length),
                        const SizedBox(width: 8),
                        _buildFilterChip('Female',
                            audioFiles.where((f) => f.prediction == 'Female').length),
                        const SizedBox(width: 8),
                        _buildFilterChip('Male',
                            audioFiles.where((f) => f.prediction == 'Male').length),
                        const SizedBox(width: 8),
                        _buildFilterChip(
                            'Undetermined',
                            audioFiles
                                .where((f) => f.prediction == 'Undetermined')
                                .length),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // List
                  Expanded(
                    child: isLoading
                        ? const LoadingScreen(message: "Reading the archive…")
                        : displayFiles.isEmpty
                            ? _buildEmptyState()
                            : RefreshIndicator(
                                onRefresh: loadAudioFiles,
                                color: textcolor,
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.9),
                                child: _buildGroupedList(displayFiles),
                              ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, int count) {
    final isSelected = filterGender == label;
    return GestureDetector(
      onTap: () {
        setState(() {
          filterGender = label;
          expandedIndex = null;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? textcolor : Colors.white.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? null
              : Border.all(
                  color: textcolor.withValues(alpha: 0.10),
                  width: 0.5,
                ),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: GoogleFonts.quicksand(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : textcolor,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.22)
                    : textcolor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: GoogleFonts.quicksand(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? Colors.white
                      : textcolor.withValues(alpha: 0.7),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Groups files by their createdAt date and renders a date divider between groups.
  Widget _buildGroupedList(List<AudioFileWithMetadata> files) {
    // Build a flat sequence of [divider, card, card, divider, card...]
    // by walking the already-sorted (newest-first) list.
    final items = <Widget>[];
    String? lastBucket;

    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      final bucket = _bucketFor(f.createdAt);

      if (bucket != lastBucket) {
        items.add(_DateDivider(label: bucket));
        lastBucket = bucket;
      }

      final isExpanded = expandedIndex == i;
      items.add(_buildSpecimenCard(f, i, isExpanded));
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: items,
    );
  }

  String _bucketFor(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(d).inDays;

    if (diff == 0) return 'TODAY';
    if (diff == 1) return 'YESTERDAY';
    if (diff < 7) return 'THIS WEEK';

    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];

    if (dt.year == now.year) {
      return '${months[dt.month - 1].toUpperCase()}';
    }
    return '${months[dt.month - 1].toUpperCase()} ${dt.year}';
  }

  Widget _buildEmptyState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        Center(
          child: Column(
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.4),
                  border: Border.all(
                    color: textcolor.withValues(alpha: 0.1),
                    width: 0.5,
                  ),
                ),
                child: Icon(
                  Icons.menu_book_outlined,
                  size: 44,
                  color: textcolor.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                filterGender == 'All'
                    ? 'The journal is empty'
                    : 'No $filterGender specimens',
                style: getSerifHeading(size: 22),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  filterGender == 'All'
                      ? 'Record or upload a duckling to start your field journal.'
                      : 'Try a different filter, or capture a new specimen.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.quicksand(
                    fontSize: 13,
                    color: textcolor.withValues(alpha: 0.6),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // SPECIMEN CARD
  // ===========================================================================

  Widget _buildSpecimenCard(
      AudioFileWithMetadata fileData, int index, bool isExpanded) {
    final fileName = fileData.file.uri.pathSegments.last;
    final fileStat = File(fileData.file.path).statSync();
    final fileSize = (fileStat.size / 1024).toStringAsFixed(1);
    final timeStr =
        '${fileData.createdAt.hour.toString().padLeft(2, '0')}:${fileData.createdAt.minute.toString().padLeft(2, '0')}';

    // Per-prediction accent — matches the new palette.
    Color accent;
    IconData icon;
    switch (fileData.prediction) {
      case 'Male':
        accent = textcolor;
        icon = Icons.male_rounded;
        break;
      case 'Female':
        accent = ducklingYellowDark;
        icon = Icons.female_rounded;
        break;
      default:
        accent = textcolor.withValues(alpha: 0.45);
        icon = Icons.help_outline_rounded;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () {
          setState(() {
            expandedIndex = isExpanded ? null : index;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: isExpanded ? 0.62 : 0.5),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isExpanded
                  ? accent.withValues(alpha: 0.4)
                  : textcolor.withValues(alpha: 0.10),
              width: isExpanded ? 1.2 : 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: textcolor.withValues(alpha: isExpanded ? 0.10 : 0.06),
                blurRadius: isExpanded ? 18 : 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    // Gender badge
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accent.withValues(alpha: 0.18),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.35),
                          width: 1,
                        ),
                      ),
                      child: Icon(icon, color: accent, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                fileData.prediction,
                                style: getSerifHeading(
                                  size: 18,
                                  color: textcolor,
                                ),
                              ),
                              if (fileData.confidence > 0) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: accent.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${fileData.confidence.toStringAsFixed(0)}%',
                                    style: GoogleFonts.quicksand(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: accent,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            fileName,
                            style: GoogleFonts.quicksand(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: textcolor.withValues(alpha: 0.65),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                timeStr,
                                style: getCapsLabel(size: 9, opacity: 0.5),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                width: 3,
                                height: 3,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: textcolor.withValues(alpha: 0.3),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                '$fileSize KB',
                                style: getCapsLabel(size: 9, opacity: 0.5),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      duration: const Duration(milliseconds: 200),
                      turns: isExpanded ? 0.5 : 0,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: textcolor.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
              if (isExpanded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: Column(
                    children: [
                      Container(
                        height: 0.5,
                        color: textcolor.withValues(alpha: 0.12),
                      ),
                      const SizedBox(height: 14),
                      if (fileData.totalClips > 0) ...[
                        _buildClipAnalysis(fileData),
                        const SizedBox(height: 14),
                      ],
                      _PondAudioPlayer(
                        audioPlayer: audioPlayer,
                        filePath: fileData.file.path,
                        onDelete: () => deleteAudio(fileData, index),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClipAnalysis(AudioFileWithMetadata fileData) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: textcolor.withValues(alpha: 0.08),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CLIP ANALYSIS', style: getCapsLabel(size: 10, opacity: 0.55)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatChip(
                  'Total', fileData.totalClips, textcolor.withValues(alpha: 0.6)),
              _buildStatChip('Female', fileData.femaleClips, ducklingYellowDark),
              _buildStatChip('Male', fileData.maleClips, textcolor),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, int count, Color color) {
    return Column(
      children: [
        Text(label, style: getCapsLabel(size: 9, opacity: 0.5)),
        const SizedBox(height: 5),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: color.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
          child: Text(
            count.toString(),
            style: GoogleFonts.quicksand(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// DATE DIVIDER
// =============================================================================

class _DateDivider extends StatelessWidget {
  final String label;
  const _DateDivider({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 14, 2, 10),
      child: Row(
        children: [
          Text(label, style: getCapsLabel(size: 10, opacity: 0.55)),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 0.5,
              color: textcolor.withValues(alpha: 0.18),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// POND-THEMED AUDIO PLAYER (replaces _MaterialAudioPlayer)
// =============================================================================

class _PondAudioPlayer extends StatelessWidget {
  final AudioPlayerService audioPlayer;
  final String filePath;
  final VoidCallback onDelete;

  const _PondAudioPlayer({
    required this.audioPlayer,
    required this.filePath,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: audioPlayer.onUpdate,
      builder: (context, snapshot) {
        final isCurrent = audioPlayer.currentlyPlaying == filePath;
        final total = audioPlayer.totalDuration?.inSeconds.toDouble() ?? 1;
        final value = isCurrent
            ? audioPlayer.currentPosition.inSeconds
                .toDouble()
                .clamp(0.0, total)
            : 0.0;
        final isPlaying = isCurrent && !audioPlayer.isPaused;

        return Column(
          children: [
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: secondColor,
                inactiveTrackColor: textcolor.withValues(alpha: 0.15),
                thumbColor: ducklingYellowDark,
                overlayColor: secondColor.withValues(alpha: 0.2),
              ),
              child: Slider(
                min: 0,
                max: total,
                value: value,
                onChanged: (val) {
                  if (isCurrent) {
                    audioPlayer.seek(Duration(seconds: val.toInt()));
                  }
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isCurrent
                        ? audioPlayer.formatDuration(audioPlayer.currentPosition)
                        : "00:00",
                    style: GoogleFonts.quicksand(
                      color: textcolor.withValues(alpha: 0.6),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    isCurrent
                        ? audioPlayer.formatDuration(
                            audioPlayer.totalDuration ?? Duration.zero)
                        : "00:00",
                    style: GoogleFonts.quicksand(
                      color: textcolor.withValues(alpha: 0.6),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _IconBtn(
                  icon: Icons.replay_10_rounded,
                  onTap: () =>
                      audioPlayer.rewind(const Duration(seconds: 10)),
                  tint: textcolor.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 14),
                GestureDetector(
                  onTap: () {
                    if (isPlaying) {
                      audioPlayer.pause();
                    } else {
                      audioPlayer.play(filePath);
                    }
                  },
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: secondColor,
                      boxShadow: [
                        BoxShadow(
                          color: ducklingYellowDark.withValues(alpha: 0.5),
                          blurRadius: 14,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Icon(
                      isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 28,
                      color: textcolor,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                _IconBtn(
                  icon: Icons.forward_10_rounded,
                  onTap: () =>
                      audioPlayer.forward(const Duration(seconds: 10)),
                  tint: textcolor.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 18),
                _IconBtn(
                  icon: Icons.delete_outline_rounded,
                  onTap: onDelete,
                  tint: recordRed,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color tint;
  const _IconBtn({required this.icon, required this.onTap, required this.tint});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.4),
          border: Border.all(
            color: tint.withValues(alpha: 0.25),
            width: 0.5,
          ),
        ),
        child: Icon(icon, size: 20, color: tint),
      ),
    );
  }
}