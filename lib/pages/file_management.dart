import 'package:flutter/material.dart';
import 'package:etech/style/mainpage_style.dart';
import 'dart:io';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';

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
     // papaltan to  ng either applicationdocuments or externalStorage
    final directory = await getExternalStorageDirectory();
    // directory != null kapag external storage : directory != false kapag application Documents
    if (directory != null) {
      final audioDir = Directory(directory.path);
      // List all files in the directory and filter for .aac files
      final files = audioDir.listSync();
      setState(() {
        audioFiles = files.where((file) => file.path.endsWith(".aac")).toList(); 
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
    
   // print("Playing audio from: $path");  // For debugging
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF7EC59), 
      appBar: AppBar(
        title: Text('File Management'),
        backgroundColor: Colors.orange,
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
                  return ListTile(
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
                  );
                },
              ),
      ),
    );
  }
}
