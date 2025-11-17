# --- INSTALL THESE FIRST ---
# pip install flask librosa pydub numpy pandas scikit-learn joblib

import os
import tempfile
import shutil
import base64
from collections import Counter

from flask import Flask, request, jsonify
from werkzeug.utils import secure_filename
from pydub import AudioSegment, silence

import numpy as np
import pandas as pd
import librosa
import joblib

app = Flask(__name__)

# -------------------------------
# 🔥 LOAD MODEL & SCALER
# -------------------------------
model = joblib.load("duckling_svm_rbf_day4-13.pkl")
scaler = joblib.load("duckling_scaler_day4-13.pkl")

# -------------------------------
# 🔥 SETTINGS
# -------------------------------
CLIP_LENGTH_MS = 3000
MIN_SILENCE_LEN = 500
SILENCE_THRESH = -45

# -------------------------------
# 🔥 FEATURE EXTRACTION
# -------------------------------
def extract_features(y, sr):
    y = librosa.util.normalize(y)

    mfccs = np.mean(librosa.feature.mfcc(y=y, sr=sr, n_mfcc=13).T, axis=0)
    spectral_centroid = np.mean(librosa.feature.spectral_centroid(y=y, sr=sr))
    spectral_rolloff = np.mean(librosa.feature.spectral_rolloff(y=y, sr=sr))
    zero_crossing_rate = np.mean(librosa.feature.zero_crossing_rate(y))
    pitches, _ = librosa.piptrack(y=y, sr=sr)
    pitch = np.mean(pitches[pitches > 0]) if np.any(pitches > 0) else 0

    return np.hstack([mfccs, spectral_centroid, spectral_rolloff, zero_crossing_rate, pitch])

# -------------------------------
# 🔥 SQUEAK DETECTION
# -------------------------------
def detect_squeak_frames(y, sr, hop=256, win=512):
    energy = librosa.feature.rms(y=y, frame_length=win, hop_length=hop)[0]
    centroid = librosa.feature.spectral_centroid(y=y, sr=sr, hop_length=hop)[0]
    energy_th = np.percentile(energy, 70)
    freq_th = 3800
    valid = (energy > energy_th) & (centroid > freq_th)
    return valid

def extract_squeak_features(file_path):
    y, sr = librosa.load(file_path, sr=None)
    y = librosa.util.normalize(y)
    hop = 256
    valid_frames = detect_squeak_frames(y, sr, hop=hop)
    if np.any(valid_frames):
        mfcc = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=13, hop_length=hop)
        squeak_mfcc = mfcc[:, valid_frames]
        mfcc_mean = np.mean(squeak_mfcc, axis=1)
        spectral_centroid = np.mean(librosa.feature.spectral_centroid(y=y, sr=sr, hop_length=hop))
        spectral_rolloff = np.mean(librosa.feature.spectral_rolloff(y=y, sr=sr, hop_length=hop))
        zero_crossing_rate = np.mean(librosa.feature.zero_crossing_rate(y, hop_length=hop))
        pitches, _ = librosa.piptrack(y=y, sr=sr, hop_length=hop)
        pitch = np.mean(pitches[pitches > 0]) if np.any(pitches > 0) else 0
        return np.hstack([mfcc_mean, spectral_centroid, spectral_rolloff, zero_crossing_rate, pitch])
    return None

# -------------------------------
# 🔥 AUDIO PREPROCESSING FOR FULL AUDIO
# -------------------------------
def preprocess_audio_clips(file_path):
    ext = os.path.splitext(file_path)[1].lower()
    if ext in [".mp3", ".m4a", ".aac"]:
        audio_temp = AudioSegment.from_file(file_path, format=ext.replace('.', ''))
        wav_path = file_path.rsplit(".", 1)[0] + ".wav"
        audio_temp.export(wav_path, format="wav")
        file_path = wav_path

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
    temp_dir = tempfile.mkdtemp()
    for i, start in enumerate(range(0, len(combined), CLIP_LENGTH_MS)):
        clip = combined[start:start + CLIP_LENGTH_MS]
        if len(clip) > 1000:
            clip_name = os.path.join(temp_dir, f"clip_{i+1}.wav")
            clip.export(clip_name, format="wav")
            clip_paths.append(clip_name)
    return clip_paths, temp_dir

# -------------------------------
# 🔥 STATUS ENDPOINT
# -------------------------------
@app.route("/status", methods=["GET"])
def status():
    try:
        if model is None or scaler is None:
            return jsonify({"status": "Model or scaler not loaded"}), 500
        return jsonify({"status": "Server is running"}), 200
    except Exception as e:
        return jsonify({"status": f"Server error: {str(e)}"}), 503

# -------------------------------
# 🔥 PREDICT ENDPOINT
# -------------------------------
@app.route("/predict", methods=["POST"])
def predict():
    audio_file = request.files.get("audio")
    if not audio_file:
        return jsonify({"error": "No audio file uploaded"}), 400

    filename = secure_filename(audio_file.filename)
    temp_path = os.path.join(tempfile.gettempdir(), filename)
    audio_file.save(temp_path)

    try:
        # 1️⃣ Try squeak detection first
        features = extract_squeak_features(temp_path)
        predictions = []
        confidences = []

        if features is not None:
            features_scaled = scaler.transform([features])
            prob = model.predict_proba(features_scaled)[0]
            pred = model.classes_[np.argmax(prob)]
            conf = float(np.max(prob) * 100)
            predictions.append(pred)
            confidences.append(conf)
        else:
            # 2️⃣ Use full audio clips for prediction
            clip_paths, temp_dir = preprocess_audio_clips(temp_path)
            if not clip_paths:
                return jsonify({"error": "Audio too silent or too short"}), 400

            for clip_path in clip_paths:
                f = extract_features(clip_path).reshape(1, -1)
                f_scaled = scaler.transform(f)
                prob = model.predict_proba(f_scaled)[0]
                pred = model.classes_[np.argmax(prob)]
                conf = float(np.max(prob) * 100)
                predictions.append(pred)
                confidences.append(conf)

        # Majority vote
        summary = Counter(predictions)
        majority_class = max(summary, key=summary.get)
        avg_conf = round(np.mean(confidences), 2)

        # Encode first clip
        with open(temp_path, "rb") as f:
            wav_base64 = base64.b64encode(f.read()).decode("utf-8")

        return jsonify({
            "prediction": majority_class,
            "confidence": avg_conf,
            "wav_base64": wav_base64
        })

    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)
        if 'temp_dir' in locals() and os.path.exists(temp_dir):
            shutil.rmtree(temp_dir)

# -------------------------------
# 🔥 RUN SERVER
# -------------------------------
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
