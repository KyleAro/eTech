# --- INSTALL THESE FIRST ---
# pip install librosa pydub numpy pandas scikit-learn joblib

import os
from pydub import AudioSegment, silence
import numpy as np
import pandas as pd
import librosa
import joblib
from collections import Counter
import shutil

# === LOAD TRAINED MODEL & SCALER ===
model = joblib.load("duckling_svm_rbf_day4-13.pkl")
scaler = joblib.load("duckling_scaler_day4-13.pkl")

# === SETTINGS ===
INPUT_FILE = "Raw datasets/Day11_girl/f5-11.m4a"  # <-- your file here
TEMP_FOLDER = "temp_clips"
OUTPUT_BASE = "predicted_dataset"   # final labeled dataset folder
CLIP_LENGTH_MS = 3000
MIN_SILENCE_LEN = 500
SILENCE_THRESH = -45

# === FEATURE EXTRACTION ===
def extract_features(file_path):
    y, sr = librosa.load(file_path, sr=None)
    y = librosa.util.normalize(y)

    mfccs = np.mean(librosa.feature.mfcc(y=y, sr=sr, n_mfcc=13).T, axis=0)
    spectral_centroid = np.mean(librosa.feature.spectral_centroid(y=y, sr=sr))
    spectral_rolloff = np.mean(librosa.feature.spectral_rolloff(y=y, sr=sr))
    zero_crossing_rate = np.mean(librosa.feature.zero_crossing_rate(y))
    pitches, magnitudes = librosa.piptrack(y=y, sr=sr)
    pitch = np.mean(pitches[pitches > 0]) if np.any(pitches > 0) else 0

    return np.hstack([mfccs, spectral_centroid, spectral_rolloff, zero_crossing_rate, pitch])

# === STEP 1: CLEAN AUDIO (REMOVE DEAD AIR + SPLIT INTO 3s) ===
def preprocess_audio(file_path):
    print("🎧 Cleaning and splitting audio...")
    os.makedirs(TEMP_FOLDER, exist_ok=True)

    # ✅ Auto-convert .mp3 / .m4a → .wav
    ext = os.path.splitext(file_path)[1].lower()
    if ext in [".mp3", ".m4a"]:
        print(f"🔄 Converting {ext} to WAV...")
        audio_temp = AudioSegment.from_file(file_path, format=ext.replace('.', ''))
        temp_wav_path = os.path.join(TEMP_FOLDER, "converted_temp.wav")
        audio_temp.export(temp_wav_path, format="wav")
        file_path = temp_wav_path
        print("✅ Conversion complete.\n")

    audio = AudioSegment.from_file(file_path)
    chunks = silence.split_on_silence(
        audio,
        min_silence_len=MIN_SILENCE_LEN,
        silence_thresh=SILENCE_THRESH
    )

    combined = AudioSegment.empty()
    for c in chunks:
        combined += c + AudioSegment.silent(duration=100)

    clip_paths = []
    for i, start in enumerate(range(0, len(combined), CLIP_LENGTH_MS)):
        clip = combined[start:start + CLIP_LENGTH_MS]
        if len(clip) > 1000:
            clip_name = os.path.join(TEMP_FOLDER, f"clip_{i+1}.wav")
            clip.export(clip_name, format="wav")
            clip_paths.append(clip_name)

    print(f"✅ {len(clip_paths)} clips generated for prediction.\n")
    return clip_paths

# === STEP 2: PREDICT EACH CLIP & AUTO-SORT ===
def predict_and_organize(clip_paths):
    print("🔍 Predicting and sorting clips...")
    cols = [f"mfcc{i+1}" for i in range(13)] + ["spectral_centroid", "spectral_rolloff", "zero_crossing_rate", "pitch"]

    os.makedirs(os.path.join(OUTPUT_BASE, "male"), exist_ok=True)
    os.makedirs(os.path.join(OUTPUT_BASE, "female"), exist_ok=True)

    predictions = []
    confidences = []

    for i, path in enumerate(clip_paths):
        features = extract_features(path).reshape(1, -1)
        features_df = pd.DataFrame(features, columns=cols)
        features_scaled = scaler.transform(features_df)

        prob = model.predict_proba(features_scaled)[0]
        pred = model.classes_[np.argmax(prob)]
        conf = round(max(prob) * 100, 2)

        # Move and rename
        dest_folder = os.path.join(OUTPUT_BASE, pred)
        new_name = f"{pred}_clip_{i+1}.wav"
        dest_path = os.path.join(dest_folder, new_name)
        shutil.move(path, dest_path)

        print(f"{os.path.basename(path)} → {pred} ({conf}%) → saved as {new_name}")

        predictions.append(pred)
        confidences.append(conf)

    # === FINAL SUMMARY ===
    print("\n📊 PREDICTION SUMMARY 📊")
    summary = Counter(predictions)
    total = len(predictions)
    avg_conf = round(np.mean(confidences), 2)

    print(f"Total clips processed: {total}")
    print(f"Male clips: {summary.get('male', 0)}")
    print(f"Female clips: {summary.get('female', 0)}")
    print(f"Average confidence: {avg_conf}%")

    # Optional: print majority class
    majority = max(summary, key=summary.get)
    print(f"\n🎯 Final Majority Prediction: {majority.upper()}")
    print("✅ All files saved in:", OUTPUT_BASE)

# === RUN ===
if __name__ == "__main__":
    clips = preprocess_audio(INPUT_FILE)
    predict_and_organize(clips)
