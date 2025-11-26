import 'dart:io';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:path_provider/path_provider.dart';

class AudioProcessor {

  /// -----------------------------------------
  /// 1. FULL PIPELINE (remove dead air → isolate duckling sound)
  /// -----------------------------------------
  static Future<String> processAudio(String inputPath) async {
    print("\n============================");
    print("🎧 Starting audio processing");
    print("============================");

    final dir = await getTemporaryDirectory();
    final ext = inputPath.split('.').last;
    final outputFile = File(
      '${dir.path}/processed_${DateTime.now().millisecondsSinceEpoch}.$ext',
    );

    /// FFmpeg filter chain: dead air removal → duckling isolation
    final command =
        '-i "$inputPath" '
        '-af "silenceremove=start_periods=0:start_threshold=-25dB:start_silence=0.5:'
        'stop_periods=0:stop_threshold=-25dB:stop_silence=0.5,'
        'arnndn=model=assets/rnnoise-models/rnnoise.ncnn" '
        '"${outputFile.path}"';

    print("🔇 Executing pipeline: Dead air removal + Duckling isolation\n$command");

    await FFmpegKit.execute(command);

    if (!await outputFile.exists()) {
      throw Exception("Audio processing failed");
    }

    print("🎉 FINAL processed file ready: ${outputFile.path}");
    return outputFile.path;
  }

  /// -----------------------------------------
  /// 2. CONVERT ANY AUDIO TO WAV
  /// -----------------------------------------
  static Future<String> convertToWav(String inputPath) async {
    final dir = await getTemporaryDirectory();
    final outputFile = File(
      '${dir.path}/converted_${DateTime.now().millisecondsSinceEpoch}.wav',
    );

    final command = '-i "$inputPath" -ar 44100 -ac 1 "${outputFile.path}"';

    print("🔊 Converting to WAV\n$command");

    await FFmpegKit.execute(command);

    if (!await outputFile.exists()) {
      throw Exception("Conversion to WAV failed");
    }

    print("✅ WAV file ready: ${outputFile.path}");
    return outputFile.path;
  }
}
