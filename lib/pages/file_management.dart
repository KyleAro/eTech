import 'package:etech/pages/MainPage.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FileManagement extends StatefulWidget {
  @override
  _FileManagementState createState() => _FileManagementState();
}

class _FileManagementState extends State<FileManagement> {
  List<FileSystemEntity> audioFiles = [];
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  bool isLoading = true;

  String? currentlyPlaying;
  bool isPaused = false;

  Duration currentPosition = Duration.zero;
  Duration? totalDuration;

  // For expansion state
  List<bool> expandedStates = [];

  @override
  void initState() {
    super.initState();
    _initPlayer();
    loadAudioFiles();
  }

  Future<void> _initPlayer() async {
    await _player.openPlayer();
    _player.onProgress!.listen((event) {
  if (mounted && currentlyPlaying != null) {
    setState(() {
      currentPosition = event.position;
      totalDuration = event.duration;
    });
  }
});


  }

  Future<void> loadAudioFiles() async {
    setState(() => isLoading = true);

    if (Platform.isAndroid) {
      await [
        Permission.storage,
        Permission.manageExternalStorage,
      ].request();
    }

    final directory = await getExternalStorageDirectory();
    if (directory != null) {
      try {
        final files = await Directory(directory.path)
            .list()
            .where((file) => file.path.toLowerCase().endsWith(".aac"))
            .toList();

        setState(() {
          audioFiles = files;
          expandedStates = List<bool>.filled(files.length, false, growable: true);

          isLoading = false;
        });
      } catch (e) {
        //debug lang yung print
        print("⚠️ Error reading files: $e");
        setState(() => isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _player.stopPlayer();
    _player.closePlayer();
    super.dispose();
  }

  void _playAudio(String path) async {
    try {
      if (_player.isPlaying && currentlyPlaying == path) {
        await _player.pausePlayer();
        setState(() => isPaused = true);
      } else if (_player.isPaused && currentlyPlaying == path) {
        await _player.resumePlayer();
        setState(() => isPaused = false);
      } else {
        if (_player.isPlaying || _player.isPaused) {
          await _player.stopPlayer();
        }

        setState(() {
          currentlyPlaying = path;
          isPaused = false;
          currentPosition = Duration.zero;
          totalDuration = null;
        });

        await _player.startPlayer(
          fromURI: path,
          whenFinished: () {
            if (mounted) {
              setState(() {
                currentlyPlaying = null;
                isPaused = false;
                currentPosition = Duration.zero;
                totalDuration = null;
              });
            }
          },
        );
      }
    } catch (e) {
      print("Error while playing audio: $e");
    }
  }

 Future<void> seekAudio(double value) async {
  if (currentlyPlaying != null && (_player.isPlaying || _player.isPaused)) {
    final newPosition = Duration(milliseconds: value.toInt());
    await _player.seekToPlayer(newPosition);
    setState(() {
      currentPosition = newPosition;
    });
  }
}
Future<void> deleteAudio(FileSystemEntity file, int index) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete File'),
      content: Text('Are you sure you want to delete "${file.uri.pathSegments.last}"?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );

  if (confirm == true) {
    try {
      final fileName = file.uri.pathSegments.last;
      final ref = FirebaseStorage.instance.ref().child('Undetermined Ducklings/$fileName');

      // 🔹 Try deleting from Firebase, but continue if not found
      try {
        await ref.delete();
        print("✅ Deleted $fileName from Firebase Storage");
      } on FirebaseException catch (e) {
        if (e.code == 'object-not-found') {
          print("⚠️ $fileName not found on Firebase — skipping Firebase delete");
        } else {
          rethrow;
        }
      }
      // 🔹 Delete from Firestore
      final firestore = FirebaseFirestore.instance;
      final snapshot = await firestore
          .collection("Undetermined") // <-- Change if your collection name is different
          .where("file_name", isEqualTo: fileName)
          .get();

      for (var doc in snapshot.docs) {
        await firestore.collection("Undetermined").doc(doc.id).delete();
        print("✅ Deleted $fileName from Firestore");
      }
      // 🔹 Delete locally
      final fileToDelete = File(file.path);
      if (await fileToDelete.exists()) {
        await fileToDelete.delete();
        print("🗑️ Deleted $fileName locally");
      }

      // 🔹 Update UI immediately
      setState(() {
        audioFiles.removeAt(index);
        expandedStates.removeAt(index);
        if (currentlyPlaying == file.path) {
          _player.stopPlayer();
          currentlyPlaying = null;
          isPaused = false;
          currentPosition = Duration.zero;
          totalDuration = null;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted $fileName from local and/or Firebase storage')),
      );
    } catch (e) {
      print("❌ Failed to delete file: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete file: $e')),
      );
    }
  }
}
  String formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return "${twoDigits(d.inMinutes.remainder(60))}:${twoDigits(d.inSeconds.remainder(60))}";
  }
void rewind10Seconds(String path) async {
  if (currentlyPlaying == path && (_player.isPlaying || _player.isPaused)) {
    final newPosition = currentPosition - const Duration(seconds: 10);
    final safePosition = newPosition < Duration.zero ? Duration.zero : newPosition;

    await _player.seekToPlayer(safePosition);
    setState(() {
      currentPosition = safePosition;
    });
  }
}

void forward10Seconds(String path) async {
  if (currentlyPlaying == path && (_player.isPlaying || _player.isPaused)) {
    final duration = totalDuration ?? Duration.zero;
    final newPosition = currentPosition + const Duration(seconds: 10);
    final safePosition = newPosition > duration ? duration : newPosition;

    await _player.seekToPlayer(safePosition);
    setState(() {
      currentPosition = safePosition;
    });
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
          ? const Center(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Color.fromARGB(255, 211, 180, 3)),
            const SizedBox(height: 16),
            Text(
              "Please Wait...",
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),)
          : RefreshIndicator(
              onRefresh: loadAudioFiles,
              color: const Color.fromARGB(255, 209, 212, 10),
              backgroundColor: Colors.black,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
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
                          body: Container(
                            padding: const EdgeInsets.all(12.0),
                            color: Colors.grey[850],
                            child: Column(
                              children: [
                               SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                                        overlayShape: SliderComponentShape.noOverlay,
                                      ),
                                      child: Slider(
                                        min: 0,
                                        max: (currentlyPlaying == file.path && totalDuration != null)
                                            ? totalDuration!.inSeconds.toDouble()
                                            : 1,
                                        value: (currentlyPlaying == file.path)
                                              ? currentPosition.inSeconds
                                                  .clamp(0, (totalDuration?.inSeconds.toDouble() ?? 1))
                                                  .toDouble()
                                              : 0,
                                        activeColor: Colors.amber,
                                        inactiveColor: Colors.white.withOpacity(0.3),
                                        onChanged: (value) {
                                          if (currentlyPlaying == file.path && totalDuration != null) {
                                            final newPosition = Duration(seconds: value.toInt());
                                            setState(() => currentPosition = newPosition);
                                          }
                                        },
                                        onChangeEnd: (value) async {
                                          if (currentlyPlaying == file.path && totalDuration != null) {
                                            final newPosition = Duration(seconds: value.toInt());
                                            await _player.seekToPlayer(newPosition);
                                          }
                                        },
                                      ),
                                    ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      formatDuration(currentPosition),
                                      style: const TextStyle(color: Colors.white70),
                                    ),
                                    Text(
                                      formatDuration(totalDuration ?? Duration.zero),
                                      style: const TextStyle(color: Colors.white70),
                                    ),
                                  ],
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Center controls
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
                      IconButton(
                        icon: const Icon(Icons.replay_10, color: Colors.white),
                        iconSize: 32,
                        onPressed: () => rewind10Seconds(file.path),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        icon: Icon(
                          currentlyPlaying == file.path && !isPaused
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_fill,
                          color: Colors.white,
                        ),
                        iconSize: 40,
                        onPressed: () => _playAudio(file.path),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        icon: const Icon(Icons.forward_10, color: Colors.white),
                        iconSize: 32,
                        onPressed: () => forward10Seconds(file.path),
                      ),
                    ],
                  ),
            // Delete button on the far right
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.redAccent),
              iconSize: 28,
              onPressed: () => deleteAudio(file, index),
            ),
          ],
        )

                                  ],
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
            ),
    );
  }
}
