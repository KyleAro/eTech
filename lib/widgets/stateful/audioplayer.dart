import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

class AudioPlayerService {
  final AudioPlayer _player = AudioPlayer();

  String? currentlyPlaying;
  bool isPaused = false;
  bool isFinished = false;

  Duration currentPosition = Duration.zero;
  Duration? totalDuration;

  final StreamController<void> _updateController = StreamController.broadcast();
  Stream<void> get onUpdate => _updateController.stream;

  AudioPlayerService() {
    _player.onPositionChanged.listen((pos) {
      if (currentlyPlaying != null) {
        currentPosition = pos;
        _updateController.add(null);
      }
    });

    _player.onPlayerComplete.listen((event) {
      currentlyPlaying = null;
      isPaused = false;
      isFinished = true;
      currentPosition = Duration.zero;
      totalDuration = null;
      _updateController.add(null);
    });
  }

  Future<void> play(String path) async {
    if (_player.state == PlayerState.playing && currentlyPlaying == path) {
      await pause();
      return;
    }

    if (_player.state == PlayerState.paused && currentlyPlaying == path) {
      await resume();
      return;
    }

    await _player.stop();

    currentlyPlaying = path;
    isPaused = false;
    isFinished = false;
    currentPosition = Duration.zero;

    await _player.play(DeviceFileSource(path));
    totalDuration = await _player.getDuration();
    _updateController.add(null);
  }

  Future<void> pause() async {
    await _player.pause();
    isPaused = true;
    _updateController.add(null);
  }

  Future<void> resume() async {
    await _player.resume();
    isPaused = false;
    _updateController.add(null);
  }

  Future<void> stop() async {
    await _player.stop();
    currentlyPlaying = null;
    isPaused = false;
    isFinished = true;
    currentPosition = Duration.zero;
    totalDuration = null;
    _updateController.add(null);
  }

  Future<void> seek(Duration position) async {
    if (currentlyPlaying != null) {
      await _player.seek(position);
      currentPosition = position;
      _updateController.add(null);
    }
  }

  void rewind(Duration duration) {
    if (currentlyPlaying != null) {
      final newPos = currentPosition - duration;
      seek(newPos < Duration.zero ? Duration.zero : newPos);
    }
  }

  void forward(Duration duration) {
    if (currentlyPlaying != null && totalDuration != null) {
      final newPos = currentPosition + duration;
      seek(newPos > totalDuration! ? totalDuration! : newPos);
    }
  }

  String formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return "${twoDigits(d.inMinutes.remainder(60))}:${twoDigits(d.inSeconds.remainder(60))}";
  }

  void dispose() {
    _player.dispose();
    _updateController.close();
  }
}

/// Reusable widget for Slider + Player Controls
class AudioPlayerControls extends StatelessWidget {
  final AudioPlayerService audioPlayer;
  final String filePath;

  const AudioPlayerControls({
    Key? key,
    required this.audioPlayer,
    required this.filePath,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: audioPlayer.onUpdate,
      builder: (context, snapshot) {
        final isCurrent = audioPlayer.currentlyPlaying == filePath;
        final totalSeconds = audioPlayer.totalDuration?.inSeconds.toDouble() ?? 1;
        final currentSeconds = isCurrent
    ? audioPlayer.currentPosition.inSeconds.toDouble().clamp(0.0, totalSeconds)
    : 0.0;


        return Column(
          children: [
            Slider(
              min: 0,
              max: totalSeconds,
              value: currentSeconds,
              activeColor: Colors.amber,
              inactiveColor: const Color.fromARGB(94, 255, 255, 255),
              onChanged: (value) {
                if (isCurrent) audioPlayer.seek(Duration(seconds: value.toInt()));
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isCurrent ? audioPlayer.formatDuration(audioPlayer.currentPosition) : "00:00",
                  style: const TextStyle(color: Colors.white70),
                ),
                Text(
                  isCurrent ? audioPlayer.formatDuration(audioPlayer.totalDuration ?? Duration.zero) : "00:00",
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.replay_10, color: Colors.white),
                  iconSize: 60,
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
                  iconSize: 60,
                  onPressed: () => audioPlayer.play(filePath),
                ),
                const SizedBox(width: 10),
                IconButton(
                  icon: const Icon(Icons.forward_10, color: Colors.white),
                  iconSize: 60,
                  onPressed: () => audioPlayer.forward(const Duration(seconds: 10)),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
