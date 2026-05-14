# --- INSTALL THESE FIRST ---
# pip install librosa pydub numpy pandas scikit-learn joblib soundfile scipy noisereduce

import os
from pydub import AudioSegment, silence
import numpy as np
import pandas as pd
import librosa
import joblib
from collections import Counter
import shutil
import soundfile as sf

# === NEW: shared cleaning module ===
from audio_clean import clean_audio, clean_audio_to_wav_bytes

# === LOAD TRAINED MODEL & SCALER ===
# NOTE: filenames bumped to *_cleaned.pkl — these are the models trained on
# cleaned audio. Using old .pkl files here will silently degrade accuracy.
model = joblib.load(r"C:\Users\User\OneDrive - Innobyte\Desktop\etech\duckling_svm_rbf_cleaned.pkl")
scaler = joblib.load(r"C:\Users\User\OneDrive - Innobyte\Desktop\etech\duckling_scaler_cleaned.pkl")

# === SETTINGS ===
INPUT_FILE = r"C:\Users\User\OneDrive - Innobyte\Desktop\etech\lib\ducklings_api\audio_2025-11-26_23-04-31.ogg"
TEMP_FOLDER = "temp_clips"
OUTPUT_BASE = "predicted_dataset"
CLIP_LENGTH_MS = 3000
MIN_SILENCE_LEN = 500
SILENCE_THRESH = -45


# === FEATURE EXTRACTION ===
# IMPORTANT: clip files written to disk have already been cleaned upstream
# in preprocess_audio(). So this function just loads + features — no second
# cleaning pass (would be a no-op on already-cleaned audio, but wastes CPU).
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


# === STEP 1: CLEAN AUDIO (NEW: real cleaning, then split into 3s) ===
def preprocess_audio(file_path):
    print("🎧 Cleaning audio with duckling-tuned DSP pipeline...")
    os.makedirs(TEMP_FOLDER, exist_ok=True)

    # 1. Run the full cleaning pipeline (HPF + LPF + spectral gate + normalize + trim)
    y_clean, sr = clean_audio(file_path)
    if y_clean.size == 0:
        print("❌ Cleaned audio is empty (input may be too short or all silence).")
        return []

    # 2. Persist cleaned audio so pydub can do its silence-split on it.
    cleaned_wav_path = os.path.join(TEMP_FOLDER, "cleaned.wav")
    sf.write(cleaned_wav_path, y_clean, sr, subtype="PCM_16")
    print(f"✅ Cleaned audio saved → {cleaned_wav_path}  ({len(y_clean)/sr:.2f}s @ {sr}Hz)")

    # 3. Split on internal silences and recombine without the gaps.
    audio = AudioSegment.from_file(cleaned_wav_path)
    chunks = silence.split_on_silence(
        audio,
        min_silence_len=MIN_SILENCE_LEN,
        silence_thresh=SILENCE_THRESH
    )

    combined = AudioSegment.empty()
    for c in chunks:
        combined += c + AudioSegment.silent(duration=100)

    # 4. Cut into fixed 3-second clips.
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
    avg_conf = round(np.mean(confidences), 2) if confidences else 0.0

    print(f"Total clips processed: {total}")
    print(f"Male clips: {summary.get('male', 0)}")
    print(f"Female clips: {summary.get('female', 0)}")
    print(f"Average confidence: {avg_conf}%")

    if summary:
        majority = max(summary, key=summary.get)
        print(f"\n🎯 Final Majority Prediction: {majority.upper()}")
    print("✅ All files saved in:", OUTPUT_BASE)


# === RUN ===
if __name__ == "__main__":
    clips = preprocess_audio(INPUT_FILE)
    if clips:
        predict_and_organize(clips)
    else:
        print("❌ No clips to predict.")