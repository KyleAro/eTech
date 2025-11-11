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
  List<bool> expandedStates = [];
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
            .where((file) => file.path.toLowerCase().endsWith(".aac") || file.path.toLowerCase().endsWith(".wav"))
            .toList();

        setState(() {
          audioFiles = files;
          expandedStates = List<bool>.filled(files.length, false, growable: true);
          isLoading = false;
        });
      } catch (e) {
        print("⚠️ Error reading files: $e");
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> deleteAudio(FileSystemEntity file, int index) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete File'),
        content: Text('Are you sure you want to delete "${file.uri.pathSegments.last}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm != true) return;
    showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const LoadingScreen(message: "Deleting file..."),
  );

    final fileName = file.uri.pathSegments.last;
    final firestore = FirebaseFirestore.instance;
    final ref = FirebaseStorage.instance.ref().child('Undetermined Ducklings/$fileName');

    try {
      try {
        await ref.delete();
      } on FirebaseException catch (e) {
        if (e.code != 'object-not-found') print("❌ Firebase Storage deletion error: $e");
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
        expandedStates.removeAt(index);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted $fileName from local and/or Firebase storage')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete file: $e')),
      );
    }
    finally {
    Navigator.pop(context);
  }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('File Management', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
      ),
      body: isLoading
          ? const LoadingScreen(message: "Loading your audio files...")
          : RefreshIndicator(
  onRefresh: loadAudioFiles,
  color: const Color.fromARGB(255, 209, 212, 10),
  backgroundColor: Colors.black,
  child: LayoutBuilder(
    builder: (context, constraints) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionPanelList(
                elevation: 1,
                animationDuration: const Duration(milliseconds: 300),
                expansionCallback: (index, isExpanded) {
                  setState(() {
                    expandedStates[index] = isExpanded;
                  });
                },
                children: List.generate(audioFiles.length, (index) {
                  final file = audioFiles[index];
                  final isExpanded = expandedStates[index];
                  return ExpansionPanel(
                    canTapOnHeader: true,
                    backgroundColor: Colors.grey[900],
                    headerBuilder: (context, _) {
                      return ListTile(
                        title: Text(
                          file.uri.pathSegments.last,
                          style: const TextStyle(color: Colors.white),
                        ),
                      );
                    },
                    body: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        children: [
                          AudioFileSlider(
                            audioPlayer: audioPlayer,
                            filePath: file.path,
                            onDelete: () => deleteAudio(file, index),
                          ),
                        ],
                      ),
                    ),
                    isExpanded: isExpanded,
                  );
                }),
              ),
            ),
          ),
        ),
      );
    },
  ),
)
    );
  }
}


class AudioFileSlider extends StatelessWidget {
  final AudioPlayerService audioPlayer;
  final String filePath;
  final VoidCallback? onDelete; 
  final bool showDelete; 

  const AudioFileSlider({
    Key? key,
    required this.audioPlayer,
    required this.filePath,
    this.onDelete,
    this.showDelete = true, 
  }) : super(key: key);

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
            Slider(
              min: 0,
              max: total,
              value: value,
              activeColor: Colors.amber,
              inactiveColor: const Color.fromARGB(104, 255, 255, 255),
              onChanged: (val) {
                if (isCurrent) audioPlayer.seek(Duration(seconds: val.toInt()));
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isCurrent
                      ? audioPlayer.formatDuration(audioPlayer.currentPosition)
                      : "00:00",
                  style: const TextStyle(color: Colors.white70),
                ),
                Text(
                  isCurrent
                      ? audioPlayer.formatDuration(audioPlayer.totalDuration ?? Duration.zero)
                      : "00:00",
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                const SizedBox(width: 40),
                IconButton(
                  icon: const Icon(Icons.replay_10, color: Colors.white),
                  iconSize: 32,
                  onPressed: () => audioPlayer.rewind(const Duration(seconds: 10)),
                ),
                const SizedBox(width: 10),
                IconButton(
                  icon: Icon(
                    isCurrent && !audioPlayer.isPaused
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_fill,
                    color: Colors.white,
                  ),
                  iconSize: 40,
                  onPressed: () {
                    if (isCurrent && !audioPlayer.isPaused) {
                      audioPlayer.pause();
                    } else {
                      audioPlayer.play(filePath);
                    }
                  },
                ),
                const SizedBox(width: 10),
                IconButton(
                  icon: const Icon(Icons.forward_10, color: Colors.white),
                  iconSize: 32,
                  onPressed: () => audioPlayer.forward(const Duration(seconds: 10)),
                ),
                if (showDelete && onDelete != null) ...[
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                    iconSize: 28,
                    onPressed: onDelete,
                  ),
                ],
              ],
            ),
          ],
        );
      },
    );
  }
}
