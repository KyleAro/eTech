# --- INSTALL THESE FIRST ---
# pip install flask librosa pydub numpy pandas scikit-learn joblib

import os
import tempfile
import shutil
import base64
from flask import Flask, request, jsonify
import numpy as np
import pandas as pd
import librosa
import joblib
from pydub import AudioSegment, silence
from collections import Counter
from werkzeug.utils import secure_filename

app = Flask(__name__)

# -------------------------------
# 🔥 LOAD MODEL & SCALER
# -------------------------------
model = joblib.load(r"C:\Users\User\OneDrive - Innobyte\Desktop\etech\duckling_svm_rbf_day4-13.pkl")
scaler = joblib.load(r"C:\Users\User\OneDrive - Innobyte\Desktop\etech\duckling_scaler_day4-13.pkl")

# -------------------------------
# 🔥 SETTINGS
# -------------------------------
CLIP_LENGTH_MS = 3000
MIN_SILENCE_LEN = 500
SILENCE_THRESH = -45

# -------------------------------
# 🔥 FEATURE EXTRACTION
# -------------------------------
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

# -------------------------------
# 🔥 AUDIO PREPROCESSING
# -------------------------------
def preprocess_audio(file_path):
    # Auto-convert .mp3 / .m4a → .wav
    ext = os.path.splitext(file_path)[1].lower()
    if ext in [".mp3", ".m4a"]:
        audio_temp = AudioSegment.from_file(file_path, format=ext.replace('.', ''))
        temp_wav_path = file_path.rsplit(".", 1)[0] + ".wav"
        audio_temp.export(temp_wav_path, format="wav")
        file_path = temp_wav_path

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
        clip_paths, temp_dir = preprocess_audio(temp_path)
        if not clip_paths:
            return jsonify({"error": "Audio too silent or too short"}), 400

        predictions = []
        confidences = []

        for clip_path in clip_paths:
            features = extract_features(clip_path).reshape(1, -1)
            features_scaled = scaler.transform(features)
            prob = model.predict_proba(features_scaled)[0]
            pred = model.classes_[np.argmax(prob)]
            conf = float(np.max(prob) * 100)
            predictions.append(pred)
            confidences.append(conf)

        # Majority vote
        summary = Counter(predictions)
        majority_class = max(summary, key=summary.get)
        avg_conf = round(np.mean(confidences), 2)

        # Encode first clip WAV as Base64
        with open(clip_paths[0], "rb") as f:
            wav_base64 = base64.b64encode(f.read()).decode("utf-8")

        return jsonify({
            "prediction": majority_class,
            "confidence": avg_conf,
            "wav_base64": wav_base64
        })

    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir)

# -------------------------------
# 🔥 RUN SERVER (Render-ready)
# -------------------------------
if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port)
