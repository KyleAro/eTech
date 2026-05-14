import 'dart:async';
import 'package:etech/pages/MainPage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:etech/style/mainpage_style.dart';

// =============================================================================
// AUDIO PLAYER SERVICE — unchanged. Pure logic, no UI.
// =============================================================================

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

// =============================================================================
// AUDIO PLAYER CONTROLS — pond & ripples styling.
// Designed to sit inside a NeuBox or directly on the pond gradient.
// =============================================================================

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
        final totalSeconds =
            audioPlayer.totalDuration?.inSeconds.toDouble() ?? 1;
        final currentSeconds = isCurrent
            ? audioPlayer.currentPosition.inSeconds
                .toDouble()
                .clamp(0.0, totalSeconds)
            : 0.0;
        final isPlaying = isCurrent && !audioPlayer.isPaused;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Slider — pond palette
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 16),
                activeTrackColor: secondColor,
                inactiveTrackColor: textcolor.withValues(alpha: 0.15),
                thumbColor: ducklingYellowDark,
                overlayColor: secondColor.withValues(alpha: 0.2),
              ),
              child: Slider(
                min: 0,
                max: totalSeconds,
                value: currentSeconds,
                onChanged: (value) {
                  if (isCurrent) {
                    audioPlayer.seek(Duration(seconds: value.toInt()));
                  }
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
                        ? audioPlayer
                            .formatDuration(audioPlayer.currentPosition)
                        : "00:00",
                    style: GoogleFonts.quicksand(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: textcolor.withValues(alpha: 0.6),
                    ),
                  ),
                  Text(
                    isCurrent
                        ? audioPlayer.formatDuration(
                            audioPlayer.totalDuration ?? Duration.zero)
                        : "00:00",
                    style: GoogleFonts.quicksand(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: textcolor.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Controls row — rewind, big play/pause, forward
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _SkipButton(
                  icon: Icons.replay_10_rounded,
                  onTap: () =>
                      audioPlayer.rewind(const Duration(seconds: 10)),
                ),
                const SizedBox(width: 18),
                _PlayPauseButton(
                  isPlaying: isPlaying,
                  onTap: () => audioPlayer.play(filePath),
                ),
                const SizedBox(width: 18),
                _SkipButton(
                  icon: Icons.forward_10_rounded,
                  onTap: () =>
                      audioPlayer.forward(const Duration(seconds: 10)),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

// =============================================================================
// PRIVATE WIDGETS
// =============================================================================

class _PlayPauseButton extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onTap;
  const _PlayPauseButton({required this.isPlaying, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: secondColor,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.7),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: ducklingYellowDark.withValues(alpha: 0.5),
              blurRadius: 18,
              spreadRadius: isPlaying ? 3 : 1,
            ),
            BoxShadow(
              color: textcolor.withValues(alpha: 0.10),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          size: 34,
          color: textcolor,
        ),
      ),
    );
  }
}

class _SkipButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _SkipButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.5),
          border: Border.all(
            color: textcolor.withValues(alpha: 0.15),
            width: 0.5,
          ),
        ),
        child: Icon(
          icon,
          size: 22,
          color: textcolor.withValues(alpha: 0.75),
        ),
      ),
    );
  }
}