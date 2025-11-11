import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import '../../style/mainpage_style.dart';

class RecordTimer extends StatelessWidget {
  final bool isRecording;
  final Stream<RecordingDisposition>? progressStream;

  const RecordTimer({
    Key? key,
    required this.isRecording,
    required this.progressStream,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      transitionBuilder: (child, animation) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.5), // starts slightly lower
          end: Offset.zero,           
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        )),
        child: FadeTransition(
          opacity: animation,
          child: child,
        ),
      ),
      child: isRecording
          ? Column(
              key: const ValueKey('timerVisible'),
              children: [
                const SizedBox(height: 10),
                StreamBuilder<RecordingDisposition>(
                  stream: progressStream,
                  builder: (context, snapshot) {
                    final duration = snapshot.hasData
                        ? snapshot.data!.duration
                        : Duration.zero;

                    String twoDigits(int n) => n.toString().padLeft(2, '0');
                    final twoDigitMinutes =
                        twoDigits(duration.inMinutes.remainder(60));
                    final twoDigitSeconds =
                        twoDigits(duration.inSeconds.remainder(60));

                    return Text(
                      '$twoDigitMinutes : $twoDigitSeconds',
                      style: getTitleTextStyle(context).copyWith(
                        fontSize: 38, // smaller size
                        color: const Color.fromARGB(255, 255, 255, 255),
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.5,
                      ),
                    );
                  },
                ),
              ],
            )
          : const SizedBox.shrink(),
    );
  }
}
