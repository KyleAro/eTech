# --- INSTALL THESE FIRST ---
# pip install flask librosa pydub numpy pandas scikit-learn joblib

from flask import Flask, request, jsonify
from pydub import AudioSegment
import numpy as np
import pandas as pd
import librosa
import joblib
from collections import Counter
import io

# === LOAD MODEL & SCALER ===
model = joblib.load("duckling_svm_rbf_day4-13.pkl")
scaler = joblib.load("duckling_scaler_day4-13.pkl")

# === SETTINGS ===
CLIP_LENGTH_MS = 3000       # 3-second clips
OVERLAP_MS = 1500           # 50% overlap for long audio

# === FEATURE EXTRACTION ===
def extract_features(audio_bytes):
    y, sr = librosa.load(io.BytesIO(audio_bytes), sr=None)
    y = librosa.util.normalize(y)

    mfccs = np.mean(librosa.feature.mfcc(y=y, sr=sr, n_mfcc=13).T, axis=0)
    spectral_centroid = np.mean(librosa.feature.spectral_centroid(y=y, sr=sr))
    spectral_rolloff = np.mean(librosa.feature.spectral_rolloff(y=y, sr=sr))
    zero_crossing_rate = np.mean(librosa.feature.zero_crossing_rate(y))
    pitches, magnitudes = librosa.piptrack(y=y, sr=sr)
    pitch = np.mean(pitches[pitches > 0]) if np.any(pitches > 0) else 0

    return np.hstack([mfccs, spectral_centroid, spectral_rolloff, zero_crossing_rate, pitch])

# === SPLIT AUDIO INTO FIXED CLIPS WITH OVERLAP ===
def split_audio_fixed(file_bytes, clip_length_ms=CLIP_LENGTH_MS, overlap_ms=OVERLAP_MS):
    audio = AudioSegment.from_file(io.BytesIO(file_bytes))
    clips = []

    step = clip_length_ms - overlap_ms
    for start in range(0, len(audio), step):
        clip = audio[start:start + clip_length_ms]
        if len(clip) > 500:  # keep very short segments
            buf = io.BytesIO()
            clip.export(buf, format="wav")
            clips.append(buf.getvalue())

    return clips

# === PREDICT ===
def predict_clips(clips):
    cols = [f"mfcc{i+1}" for i in range(13)] + ["spectral_centroid", "spectral_rolloff", "zero_crossing_rate", "pitch"]
    predictions = []
    confidences = []

    for clip_bytes in clips:
        features = extract_features(clip_bytes).reshape(1, -1)
        features_df = pd.DataFrame(features, columns=cols)
        features_scaled = scaler.transform(features_df)

        prob = model.predict_proba(features_scaled)[0]
        pred = model.classes_[np.argmax(prob)]
        conf = round(max(prob) * 100, 2)

        predictions.append(pred)
        confidences.append(conf)

    if not predictions:
        return None, None

    # Majority vote for final prediction
    summary = Counter(predictions)
    majority_pred = max(summary, key=summary.get)
    avg_conf = round(np.mean(confidences), 2)

    return majority_pred, avg_conf

# === FLASK APP ===
app = Flask(__name__)

@app.route("/status", methods=["GET"])
def status():
    # simple endpoint to check server readiness
    return jsonify({"status": "ready"}), 200

@app.route("/predict", methods=["POST"])
def predict():
    if "file" not in request.files:
        return jsonify({"error": "No file uploaded"}), 400

    file_bytes = request.files["file"].read()
    clips = split_audio_fixed(file_bytes)

    if not clips:
        return jsonify({"error": "Audio too short or empty"}), 400

    prediction, confidence = predict_clips(clips)
    if prediction is None:
        return jsonify({"error": "Could not make prediction"}), 500

    return jsonify({"prediction": prediction, "confidence": confidence}), 200

if __name__ == "__main__":
    print("✅ Server is starting and ready to receive requests...")
    app.run(host="0.0.0.0", port=8000)
