# ===========================
#  CLEAN & CORRECTED API.PY
# ===========================

import os
import tempfile
import base64
import numpy as np
import pandas as pd
import librosa
import joblib
from flask import Flask, request, jsonify
from pydub import AudioSegment, silence
from collections import Counter

# ------------------
# FLASK SETUP
# ------------------
app = Flask(__name__)

# ------------------
# MODEL PATHS
# ------------------
MODEL_PATH = "duckling_svm_rbf_day4-13.pkl"
SCALER_PATH = "duckling_scaler_day4-13.pkl"

model = None
scaler = None

# ------------------
# SETTINGS (MUST MATCH TRAINING)
# ------------------
CLIP_LENGTH_MS = 3000
MIN_SILENCE_LEN = 500
SILENCE_THRESH = -45

# ------------------
# LOAD MODEL + SCALER
# ------------------
def load_models():
    global model, scaler
    try:
        model = joblib.load(MODEL_PATH)
        scaler = joblib.load(SCALER_PATH)
        print("✅ Model & scaler loaded.")
    except Exception as e:
        print("❌ Failed to load model/scaler:", e)
        model = None
        scaler = None

load_models()

# ------------------
# FEATURE EXTRACTION (MUST MATCH TRAINING!)
# ------------------
def extract_features(file_path):
    y, sr = librosa.load(file_path, sr=None)
    y = librosa.util.normalize(y)

    mfccs = np.mean(librosa.feature.mfcc(y=y, sr=sr, n_mfcc=13).T, axis=0)
    spectral_centroid = np.mean(librosa.feature.spectral_centroid(y=y, sr=sr))
    spectral_rolloff = np.mean(librosa.feature.spectral_rolloff(y=y, sr=sr))
    zero_crossing_rate = np.mean(librosa.feature.zero_crossing_rate(y))
    pitches, mags = librosa.piptrack(y=y, sr=sr)
    pitch = np.mean(pitches[pitches > 0]) if np.any(pitches > 0) else 0

    return np.hstack([mfccs, spectral_centroid, spectral_rolloff, zero_crossing_rate, pitch])

# ------------------
# AUDIO PREPROCESSING
# ------------------
def preprocess_audio(input_path):
    ext = os.path.splitext(input_path)[1].lower()

    # Convert MP3/M4A → WAV (training used WAV)
    if ext in [".mp3", ".m4a"]:
        audio = AudioSegment.from_file(input_path, format=ext.replace(".", ""))
        temp_wav = input_path + ".converted.wav"
        audio.export(temp_wav, format="wav")
        input_path = temp_wav

    audio = AudioSegment.from_file(input_path)

    # Remove silence
    chunks = silence.split_on_silence(
        audio,
        min_silence_len=MIN_SILENCE_LEN,
        silence_thresh=SILENCE_THRESH
    )

    combined = AudioSegment.empty()
    for c in chunks:
        combined += c + AudioSegment.silent(duration=100)

    # Save cleaned audio for playback
    cleaned_temp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
    cleaned_path = cleaned_temp.name
    combined.export(cleaned_path, format="wav")

    # Slice into 3s clips
    clip_paths = []
    for start in range(0, len(combined), CLIP_LENGTH_MS):
        clip = combined[start:start + CLIP_LENGTH_MS]
        if len(clip) > 1000:
            clip_file = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
            clip_path = clip_file.name
            clip.export(clip_path, format="wav")
            clip_paths.append(clip_path)

    return cleaned_path, clip_paths

# ------------------
# CORE PREDICTION
# ------------------
def predict_from_clips(clip_paths):
    preds = []
    confs = []
    cols = [f"mfcc{i+1}" for i in range(13)] + [
        "spectral_centroid", "spectral_rolloff", "zero_crossing_rate", "pitch"
    ]

    for clip_path in clip_paths:
        feats = extract_features(clip_path).reshape(1, -1)
        feats_df = pd.DataFrame(feats, columns=cols)
        feats_scaled = scaler.transform(feats_df)

        prob = model.predict_proba(feats_scaled)[0]
        pred = model.classes_[np.argmax(prob)]
        conf = max(prob) * 100

        preds.append(pred)
        confs.append(conf)

    majority = max(preds, key=preds.count)
    majority_conf = round((preds.count(majority) / len(preds)) * 100, 2)

    return majority, majority_conf

# ------------------
# API ROUTES
# ------------------
@app.route("/status", methods=["GET"])
def status():
    return jsonify({"status": "ok", "model_loaded": model is not None})

@app.route("/predict", methods=["POST"])
def predict():
    if "audio" not in request.files:
        return jsonify({"error": "No audio file uploaded"}), 400

    file = request.files["audio"]

    # Save uploaded file
    input_tmp = tempfile.NamedTemporaryFile(delete=False)
    input_path = input_tmp.name
    file.save(input_path)

    try:
        # Preprocess (clean + slice)
        cleaned_path, clip_paths = preprocess_audio(input_path)

        if len(clip_paths) == 0:
            return jsonify({"error": "Audio too short or silent"}), 400

        # Predict
        label, confidence = predict_from_clips(clip_paths)

        # Return cleaned audio as base64 for Flutter
        with open(cleaned_path, "rb") as f:
            wav_base64 = base64.b64encode(f.read()).decode("utf-8")

        return jsonify({
            "prediction": label.lower(),
            "confidence": confidence,
            "wav_base64": wav_base64
        })

    finally:
        # Cleanup all temp files
        if os.path.exists(input_path): os.remove(input_path)
        if os.path.exists(cleaned_path): os.remove(cleaned_path)
        for c in clip_paths:
            if os.path.exists(c): os.remove(c)

# ------------------
# RUN SERVER
# ------------------
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
