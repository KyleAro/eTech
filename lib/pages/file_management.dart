import 'package:etech/pages/MainPage.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import '../widgets/stateful/audioplayer.dart';
import '../widgets/stateless/loading_screen.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
    filterGender = widget.initialFilter ?? 'All'; // Use provided filter or default to 'All'
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
        // Get all audio files
        final files = await Directory(directory.path)
            .list()
            .where((file) =>
                file.path.toLowerCase().endsWith(".wav") ||
                file.path.toLowerCase().endsWith(".aac") ||
                file.path.toLowerCase().endsWith(".mp3") ||
                file.path.toLowerCase().endsWith(".m4a"))
            .toList();

        // Load metadata from Firestore
        final firestore = FirebaseFirestore.instance;
        List<AudioFileWithMetadata> filesWithMeta = [];

        for (var file in files) {
          final fileName = file.uri.pathSegments.last;
          
          // Try to get metadata from LocalPredictions collection
          final querySnapshot = await firestore
              .collection('LocalPredictions')
              .where('file_name', isEqualTo: fileName)
              .limit(1)
              .get();

          if (querySnapshot.docs.isNotEmpty) {
            // Has prediction data
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
              createdAt: (data['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
            ));
          } else if (fileName.contains('Undetermined')) {
            // Undetermined recording (no prediction)
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
                  ? (querySnapshot2.docs.first.data()['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now()
                  : DateTime.now(),
            ));
          }
        }

        // Sort by date (newest first)
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete All Files'),
        content: Text(
          filterGender == 'All'
              ? 'Are you sure you want to delete ALL files? This cannot be undone.'
              : 'Are you sure you want to delete all $filterGender files?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const LoadingScreen(message: "Deleting files..."),
    );

    final firestore = FirebaseFirestore.instance;
    final storage = FirebaseStorage.instance;
    final filesToDelete = filteredFiles;

    try {
      for (var fileData in filesToDelete) {
        // Delete local file
        final localFile = File(fileData.file.path);
        if (await localFile.exists()) await localFile.delete();

        final fileName = fileData.file.uri.pathSegments.last;

        // Delete from Firebase Storage
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

        // Delete from Firestore
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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            filterGender == 'All' 
                ? 'All files deleted successfully!' 
                : 'All $filterGender files deleted!',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete files: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      Navigator.pop(context);
    }
  }

  Future<void> deleteAudio(AudioFileWithMetadata fileData, int index) async {
    final fileName = fileData.file.uri.pathSegments.last;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete File'),
        content: Text('Are you sure you want to delete "$fileName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const LoadingScreen(message: "Deleting file..."),
    );

    final firestore = FirebaseFirestore.instance;
    final storage = FirebaseStorage.instance;

    try {
      // Delete from Firebase Storage
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

      // Delete from Firestore
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

      // Delete local file
      final fileToDelete = File(fileData.file.path);
      if (await fileToDelete.exists()) {
        await fileToDelete.delete();
      }

      await loadAudioFiles();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Deleted $fileName'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete file: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayFiles = filteredFiles;
    
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
      child: Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text(
            'My Recordings',
            style: TextStyle(
              color: textcolor,
              fontWeight: FontWeight.w600,
              fontSize: 20,
            ),
          ),
          centerTitle: true,
          actions: [
            if (displayFiles.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.delete_sweep, color: textcolor),
                onPressed: deleteAllRecordings,
                tooltip: 'Delete All',
              ),
          ],
        ),
        body: Column(
          children: [
            // Filter Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  _buildFilterChip('All', audioFiles.length),
                  const SizedBox(width: 8),
                  _buildFilterChip('Male', audioFiles.where((f) => f.prediction == 'Male').length),
                  const SizedBox(width: 8),
                  _buildFilterChip('Female', audioFiles.where((f) => f.prediction == 'Female').length),
                  const SizedBox(width: 8),
                  _buildFilterChip('Undetermined', audioFiles.where((f) => f.prediction == 'Undetermined').length),
                ],
              ),
            ),
            
            // File List
            Expanded(
              child: isLoading
                  ? const LoadingScreen(message: "Loading your audio files...")
                  : displayFiles.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: loadAudioFiles,
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(16),
                            itemCount: displayFiles.length,
                            itemBuilder: (context, index) {
                              final fileData = displayFiles[index];
                              final isExpanded = expandedIndex == index;
                              return _buildFileCard(fileData, index, isExpanded);
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, int count) {
    final isSelected = filterGender == label;
    return FilterChip(
      label: Text('$label ($count)'),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          filterGender = label;
          expandedIndex = null;
        });
      },
      selectedColor: const Color(0xFFFFD54F).withOpacity(0.3),
      checkmarkColor: const Color(0xFFFFD54F),
      labelStyle: TextStyle(
        color: isSelected ? const Color(0xFFFFD54F) : Colors.grey[400],
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: const Color(0xFFFFD54F).withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.mic_none,
              size: 80,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            filterGender == 'All' ? 'No Recordings Yet' : 'No $filterGender Files',
            style: TextStyle(
              color: Colors.grey[300],
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            filterGender == 'All'
                ? 'Start recording or uploading to see files here'
                : 'Try a different filter',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileCard(AudioFileWithMetadata fileData, int index, bool isExpanded) {
    final fileName = fileData.file.uri.pathSegments.last;
    final fileStat = File(fileData.file.path).statSync();
    final fileSize = (fileStat.size / 1024).toStringAsFixed(1);
    final dateStr = '${fileData.createdAt.day}/${fileData.createdAt.month}/${fileData.createdAt.year}';
    final timeStr = '${fileData.createdAt.hour.toString().padLeft(2, '0')}:${fileData.createdAt.minute.toString().padLeft(2, '0')}';

    // Color based on prediction
    Color predictionColor;
    IconData predictionIcon;
    
    switch (fileData.prediction) {
      case 'Male':
        predictionColor = Colors.blue;
        predictionIcon = Icons.male;
        break;
      case 'Female':
        predictionColor = Colors.pink;
        predictionIcon = Icons.female;
        break;
      default:
        predictionColor = Colors.grey;
        predictionIcon = Icons.help_outline;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isExpanded ? 4 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            expandedIndex = isExpanded ? null : index;
          });
        },
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Prediction Badge
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: predictionColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      predictionIcon,
                      color: predictionColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Prediction + Confidence
                        Row(
                          children: [
                            Text(
                              fileData.prediction,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: predictionColor,
                              ),
                            ),
                            if (fileData.confidence > 0) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: predictionColor.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${fileData.confidence.toStringAsFixed(1)}%',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: predictionColor,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        // File name
                        Text(
                          fileName,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        // Metadata
                        Row(
                          children: [
                            Icon(Icons.calendar_today, size: 11, color: Colors.grey[500]),
                            const SizedBox(width: 4),
                            Text(
                              '$dateStr • $timeStr',
                              style: TextStyle(color: Colors.grey[500], fontSize: 10),
                            ),
                            const SizedBox(width: 12),
                            Icon(Icons.storage, size: 11, color: Colors.grey[500]),
                            const SizedBox(width: 4),
                            Text(
                              '$fileSize KB',
                              style: TextStyle(color: Colors.grey[500], fontSize: 10),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: Colors.grey[600],
                  ),
                ],
              ),
            ),
            if (isExpanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: [
                    Divider(color: Colors.grey[800]),
                    const SizedBox(height: 16),
                    
                    // Clip Analysis (if available)
                    if (fileData.totalClips > 0) ...[
                      _buildClipAnalysis(fileData),
                      const SizedBox(height: 16),
                    ],
                    
                    // Audio Player
                    _MaterialAudioPlayer(
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
    );
  }

  Widget _buildClipAnalysis(AudioFileWithMetadata fileData) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Clip Analysis',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatChip('Total', fileData.totalClips, Colors.grey),
              _buildStatChip('Male', fileData.maleClips, Colors.blue),
              _buildStatChip('Female', fileData.femaleClips, Colors.pink),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[500],
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            count.toString(),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _MaterialAudioPlayer extends StatelessWidget {
  final AudioPlayerService audioPlayer;
  final String filePath;
  final VoidCallback onDelete;

  const _MaterialAudioPlayer({
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
            ? audioPlayer.currentPosition.inSeconds.toDouble().clamp(0.0, total)
            : 0.0;

        return Column(
          children: [
            // Slider
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: const Color(0xFFFFD54F),
                inactiveTrackColor: Colors.grey[800],
                thumbColor: const Color(0xFFFFD54F),
                overlayColor: const Color(0xFFFFD54F).withOpacity(0.2),
              ),
              child: Slider(
                min: 0,
                max: total,
                value: value,
                onChanged: (val) {
                  if (isCurrent) audioPlayer.seek(Duration(seconds: val.toInt()));
                },
              ),
            ),
            // Time labels
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isCurrent
                        ? audioPlayer.formatDuration(audioPlayer.currentPosition)
                        : "00:00",
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    isCurrent
                        ? audioPlayer.formatDuration(audioPlayer.totalDuration ?? Duration.zero)
                        : "00:00",
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Control buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.replay_10),
                  onPressed: () => audioPlayer.rewind(const Duration(seconds: 10)),
                  iconSize: 28,
                  color: Colors.grey[400],
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    if (isCurrent && !audioPlayer.isPaused) {
                      audioPlayer.pause();
                    } else {
                      audioPlayer.play(filePath);
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD54F),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.all(16),
                    shape: const CircleBorder(),
                  ),
                  child: Icon(
                    isCurrent && !audioPlayer.isPaused ? Icons.pause : Icons.play_arrow,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.forward_10),
                  onPressed: () => audioPlayer.forward(const Duration(seconds: 10)),
                  iconSize: 28,
                  color: Colors.grey[400],
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: onDelete,
                  iconSize: 28,
                  color: Colors.red[400],
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}