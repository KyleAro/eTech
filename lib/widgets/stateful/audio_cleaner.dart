import 'dart:io';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffprobe_kit.dart';

class AudioProcessor {
  /// Convert input audio to WAV mono 16-bit
  static Future<String> convertToWav(String inputPath) async {
    final dir = await getTemporaryDirectory();
    final outputFile = File('${dir.path}/converted_${DateTime.now().millisecondsSinceEpoch}.wav');

    final command = '-i "$inputPath" -ac 1 -ar 16000 -c:a pcm_s16le "${outputFile.path}"';
    print("Executing FFmpeg command (convert to WAV):\n$command");
    await FFmpegKit.execute(command);

    if (!await outputFile.exists()) throw Exception("WAV conversion failed");

    print("✅ WAV conversion succeeded: ${outputFile.path}");
    print("File size: ${await outputFile.length()} bytes");

    // Optional: check duration
    final session = await FFprobeKit.getMediaInformation(outputFile.path);
    final info = session.getMediaInformation();
    print("Duration: ${info?.getDuration()} seconds");

    return outputFile.path;
  }

  
  static Future<String> removeDeadAir(String inputPath) async {
    final dir = await getTemporaryDirectory();
    final outputFile = File('${dir.path}/deadair_removed_${DateTime.now().millisecondsSinceEpoch}.wav');

    final command =
        '-i "$inputPath" -af "silenceremove=start_periods=1:start_threshold=-15dB:start_silence=0.5:stop_periods=-1:stop_threshold=-25dB:stop_silence=0.5" "${outputFile.path}"';
    
    print("Executing FFmpeg command (remove dead air):\n$command");
    await FFmpegKit.execute(command);

    if (!await outputFile.exists()) throw Exception("Dead air removal failed");

    print("✅ Dead air removal succeeded: ${outputFile.path}");
    print("File size: ${await outputFile.length()} bytes");

    // Optional: check duration
    final session = await FFprobeKit.getMediaInformation(outputFile.path);
    final info = session.getMediaInformation();
    print("Duration after dead air removal: ${info?.getDuration()} seconds");

    return outputFile.path;
  }

  /// Full preprocessing workflow: convert -> remove dead air
  static Future<String> process(String inputPath) async {
    print("🔹 Starting preprocessing for: $inputPath");

    String wavFile = await convertToWav(inputPath);
    String cleanedFile = await removeDeadAir(wavFile);

    print("🔹 Preprocessing complete. Output file: $cleanedFile");
    return cleanedFile;
  }
}
