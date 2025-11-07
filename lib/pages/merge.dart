import 'package:etech/pages/MainPage.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:etech/style/mainpage_style.dart';

class Merger extends StatefulWidget {
  @override
  _MergeState createState() => _MergeState();
}

class _MergeState extends State<Merger> {
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
    _player.onProgress?.listen((event) {
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
          expandedStates = List.filled(files.length, false);
          isLoading = false;
        });
      } catch (e) {
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
    if (_player.isPlaying || _player.isPaused) {
      await _player.seekToPlayer(Duration(milliseconds: value.toInt()));
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

        // 🔹 Delete from Firebase Storage
        final ref = FirebaseStorage.instance.ref().child('Undetermined Ducklings/$fileName');
        await ref.delete();
        print("✅ Deleted $fileName from Firebase Storage");

        // 🔹 Delete from local storage
        final fileToDelete = File(file.path);
        if (await fileToDelete.exists()) {
          await fileToDelete.delete();
          print("🗑️ Deleted $fileName locally");
        }

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
          SnackBar(content: Text('Deleted $fileName from local and Firebase storage')),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('File Management', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: loadAudioFiles,
              color: Colors.white,
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
                                Slider(
                                  value: (currentlyPlaying == file.path)
                                      ? currentPosition.inMilliseconds.toDouble()
                                      : 0,
                                  max: (currentlyPlaying == file.path && totalDuration != null)
                                      ? totalDuration!.inMilliseconds.toDouble()
                                      : 1,
                                  onChanged: (value) => seekAudio(value),
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
                                    ElevatedButton.icon(
                                      onPressed: () => _playAudio(file.path),
                                      icon: Icon(
                                        currentlyPlaying == file.path && !isPaused
                                            ? Icons.pause
                                            : Icons.play_arrow,
                                      ),
                                      label: Text(
                                        currentlyPlaying == file.path && !isPaused
                                            ? 'Pause'
                                            : 'Play',
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    ElevatedButton.icon(
                                      onPressed: () => deleteAudio(file, index),
                                      icon: const Icon(Icons.delete),
                                      label: const Text('Delete'),
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                    ),
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
