import 'package:flutter/material.dart';
import 'package:etech/style/mainpage_style.dart';
import 'dart:io';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

class FileManagement extends StatefulWidget {
  @override
  _FileManagementState createState() => _FileManagementState();
}

class _FileManagementState extends State<FileManagement> {
  List<FileSystemEntity> audioFiles = []; // List to hold audio files
  FlutterSoundPlayer _player = FlutterSoundPlayer(); // Player to play audio

  @override
  void initState() {
    super.initState();
    loadAudioFiles(); // Load audio files when the page is initialized
    _initPlayer(); // Initialize the audio player session
  }

  Future<void> _initPlayer() async {
    await _player.openPlayer();
    await _player.startPlayer(); // Initialize the player
  }

  Future<void> loadAudioFiles() async {
    final directory = Platform.isAndroid
    ? await getExternalStorageDirectory()
    : await getApplicationDocumentsDirectory();
    if (directory != null) {
      final audioDir = Directory(directory.path);
      final files = audioDir.listSync();
      setState(() {
        audioFiles =
            files.where((file) => file.path.endsWith(".aac")).toList();
      });
    }
  }

  @override
  void dispose() {
    if (_player.isPlaying) {
      _player.stopPlayer();
    }
    super.dispose();
  }

  void _playAudio(String path) async {
    try {
      await _player.startPlayer(
        fromURI: path,
        whenFinished: () {
          print("Playback finished");
        },
      );
    } catch (e) {
      print("Error while playing audio: $e");
    }
  }

  Future<void> deleteAudio(FileSystemEntity file, int index) async {
    // Show confirmation dialog before deleting
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete File'),
        content: Text(
          'Are you sure you want to delete "${file.uri.pathSegments.last}"?',
        ),
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
        final fileToDelete = File(file.path);

        if (await fileToDelete.exists()) {
          await fileToDelete.delete();
        }

        setState(() {
          audioFiles.removeAt(index);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted ${file.uri.pathSegments.last}'),
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete file: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7EC59),
      appBar: AppBar(
        title: const Text('File Management'),
        backgroundColor: Colors.transparent,
      ),
      body: Center(
        child: audioFiles.isEmpty
            ? Text(
                'No audio files found.',
                style: getTitleTextStyle(context).copyWith(
                  fontSize: 18,
                  color: Colors.white,
                ),
              )
            : ListView.builder(
                itemCount: audioFiles.length,
                itemBuilder: (context, index) {
                  final file = audioFiles[index];

                  return Slidable(
                    key: ValueKey(file.path),
                    startActionPane: ActionPane(
                      motion: const DrawerMotion(),
                      children: [
                        SlidableAction(
                          onPressed: (context) {
                            _playAudio(file.path);
                          },
                          backgroundColor: Colors.green,
                          icon: Icons.play_arrow,
                          label: 'Play',
                        ),
                      ],
                    ),
                    endActionPane: ActionPane(
                      motion: const DrawerMotion(),
                      children: [
                        SlidableAction(
                          onPressed: (context) async {
                            await deleteAudio(file, index);
                          },
                          backgroundColor: Colors.red,
                          icon: Icons.delete,
                          label: 'Delete',
                        ),
                      ],
                    ),
                    child: ListTile(
                      title: Text(
                        file.uri.pathSegments.last,
                        style: getTitleTextStyle(context).copyWith(
                          fontSize: 16,
                          color: Colors.black,
                        ),
                      ),
                      onTap: () {
                        _playAudio(file.path);
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }
}
