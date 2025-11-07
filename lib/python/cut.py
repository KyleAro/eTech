# pip install pydub
from pydub import AudioSegment
import os

# === SETTINGS ===
input_file = "Fem01.m4a"
  # change this to your file name
output_folder = "datasets_cleaned/female1"
clip_length_ms = 4 * 1000  # 4 seconds

# === CONVERT & SPLIT ===
print("Loading audio...")
audio = AudioSegment.from_file(input_file)
duration_ms = len(audio)
os.makedirs(output_folder, exist_ok=True)

print(f"Total duration: {duration_ms / 1000:.2f} seconds")
print("Splitting into 4-second clips...")

count = 0
for start_ms in range(0, duration_ms, clip_length_ms):
    end_ms = start_ms + clip_length_ms
    clip = audio[start_ms:end_ms]
    
    # Export the clip without checking for length anymore
    count += 1
    out_name = f"female_f{count:03d}.wav"  # Renamed output
    out_path = os.path.join(output_folder, out_name)
    clip.export(out_path, format="wav")

print(f"✅ Done! Exported {count} clips to {output_folder}")
