import 'package:etech/pages/MainPage.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import '../widgets/stateful/audioplayer.dart';
import '../widgets/stateless/loading_screen.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FileManagement extends StatefulWidget {
  @override
  _FileManagementState createState() => _FileManagementState();
}

class _FileManagementState extends State<FileManagement> {
  List<FileSystemEntity> audioFiles = [];
  bool isLoading = true;
  int? expandedIndex;
  late final AudioPlayerService audioPlayer;

  @override
  void initState() {
    super.initState();
    audioPlayer = AudioPlayerService();
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
                file.path.toLowerCase().endsWith(".aac") &&
                file.path.contains("Undetermined"))
            .toList();

        setState(() {
          audioFiles = files;
          isLoading = false;
        });
      } catch (e) {
        print("⚠️ Error reading files: $e");
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> deleteAllRecordings() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete All Recordings'),
        content: const Text(
            'Are you sure you want to delete ALL recordings? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const LoadingScreen(message: "Deleting all recordings..."),
    );

    final firestore = FirebaseFirestore.instance;
    final storage = FirebaseStorage.instance;

    try {
      for (var file in audioFiles) {
        final localFile = File(file.path);
        if (await localFile.exists()) await localFile.delete();

        final fileName = file.uri.pathSegments.last;

        final ref = storage.ref().child('Undetermined Ducklings/$fileName');
        try {
          await ref.delete();
        } on FirebaseException catch (e) {
          if (e.code != 'object-not-found')
            print("❌ Firebase Storage deletion error: $e");
        }

        final snapshot = await firestore
            .collection("Undetermined")
            .where("file_name", isEqualTo: fileName)
            .get();

        for (var doc in snapshot.docs) {
          await firestore.collection("Undetermined").doc(doc.id).delete();
        }
      }

      setState(() {
        audioFiles.clear();
        expandedIndex = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All recordings deleted successfully!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete all recordings: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      Navigator.pop(context);
    }
  }

  Future<void> deleteAudio(FileSystemEntity file, int index) async {
    final fileName = file.uri.pathSegments.last;
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
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
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
    final ref =
        FirebaseStorage.instance.ref().child('Undetermined Ducklings/$fileName');

    try {
      try {
        await ref.delete();
      } on FirebaseException catch (e) {
        if (e.code != 'object-not-found')
          print("❌ Firebase Storage deletion error: $e");
      }

      final snapshot = await firestore
          .collection("Undetermined")
          .where("file_name", isEqualTo: fileName)
          .get();

      if (snapshot.docs.isNotEmpty) {
        for (var doc in snapshot.docs) {
          await firestore.collection("Undetermined").doc(doc.id).delete();
        }
      }

      final fileToDelete = File(file.path);
      if (await fileToDelete.exists()) {
        await fileToDelete.delete();
      }

      setState(() {
        audioFiles.removeAt(index);
        if (expandedIndex == index) {
          expandedIndex = null;
        } else if (expandedIndex != null && expandedIndex! > index) {
          expandedIndex = expandedIndex! - 1;
        }
      });

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
            if (audioFiles.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.delete_sweep,color: textcolor,),
                onPressed: deleteAllRecordings,
                tooltip: 'Delete All',
              ),
          ],
        ),
        body: isLoading
            ? const LoadingScreen(message: "Loading your audio files...")
            : audioFiles.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
                    onRefresh: loadAudioFiles,
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: audioFiles.length,
                      itemBuilder: (context, index) {
                        final file = audioFiles[index];
                        final isExpanded = expandedIndex == index;
                        return _buildFileCard(file, index, isExpanded);
                      },
                    ),
                  ),
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
            'No Recordings Yet',
            style: TextStyle(
              color: Colors.grey[300],
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start recording to see your files here',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileCard(FileSystemEntity file, int index, bool isExpanded) {
    final fileName = file.uri.pathSegments.last;
    final fileStat = File(file.path).statSync();
    final fileSize = (fileStat.size / 1024).toStringAsFixed(1);
    final modifiedDate = fileStat.modified;
    final dateStr =
        '${modifiedDate.day}/${modifiedDate.month}/${modifiedDate.year}';
    final timeStr =
        '${modifiedDate.hour.toString().padLeft(2, '0')}:${modifiedDate.minute.toString().padLeft(2, '0')}';

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
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD54F).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.audiotrack,
                      color: Color(0xFFFFD54F),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fileName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.calendar_today,
                                size: 12, color: Colors.grey[500]),
                            const SizedBox(width: 4),
                            Text(
                              '$dateStr • $timeStr',
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Icon(Icons.storage,
                                size: 12, color: Colors.grey[500]),
                            const SizedBox(width: 4),
                            Text(
                              '$fileSize KB',
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
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
                    _MaterialAudioPlayer(
                      audioPlayer: audioPlayer,
                      filePath: file.path,
                      onDelete: () => deleteAudio(file, index),
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
                  if (isCurrent)
                    audioPlayer.seek(Duration(seconds: val.toInt()));
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
                        ? audioPlayer.formatDuration(
                            audioPlayer.totalDuration ?? Duration.zero)
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
                  onPressed: () =>
                      audioPlayer.rewind(const Duration(seconds: 10)),
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
                    isCurrent && !audioPlayer.isPaused
                        ? Icons.pause
                        : Icons.play_arrow,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.forward_10),
                  onPressed: () =>
                      audioPlayer.forward(const Duration(seconds: 10)),
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