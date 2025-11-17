# --- INSTALL THESE FIRST ---
# pip install flask librosa pydub numpy scikit-learn joblib

import os
import numpy as np
from flask import Flask, request, jsonify
import joblib
from pydub import AudioSegment
from werkzeug.utils import secure_filename
import tempfile
import base64

app = Flask(__name__)

# -------------------------------
# 🔥 LOAD MODEL & SCALER
# -------------------------------
model = joblib.load("duckling_svm_rbf_day4-13.pkl")
scaler = joblib.load("duckling_scaler_day4-13.pkl")

# -------------------------------
# 🔥 HELPER FUNCTIONS
# -------------------------------
def sharpen_probabilities(p, temp=0.35):
    p = np.power(p, 1 / temp)
    p /= np.sum(p)
    return p

def detect_squeak_frames(y, sr, hop=256, win=512):
    energy = librosa.feature.rms(y=y, frame_length=win, hop_length=hop)[0]
    centroid = librosa.feature.spectral_centroid(y=y, sr=sr, hop_length=hop)[0]
    energy_th = np.percentile(energy, 70)
    freq_th = 3800  # Hz threshold for high-pitched squeaks
    valid = (energy > energy_th) & (centroid > freq_th)
    return valid

def extract_features_from_squeaks(file_path):
    y, sr = librosa.load(file_path, sr=None)
    y = librosa.util.normalize(y)
    hop = 256
    valid_frames = detect_squeak_frames(y, sr, hop=hop)
    if not np.any(valid_frames):
        return None  # no squeak detected

    mfcc = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=13, hop_length=hop)
    squeak_mfcc = mfcc[:, valid_frames]
    mfcc_mean = np.mean(squeak_mfcc, axis=1)

    spectral_centroid = np.mean(librosa.feature.spectral_centroid(y=y, sr=sr, hop_length=hop))
    spectral_rolloff = np.mean(librosa.feature.spectral_rolloff(y=y, sr=sr, hop_length=hop))
    zero_crossing_rate = np.mean(librosa.feature.zero_crossing_rate(y, hop_length=hop))
    pitches, magnitudes = librosa.piptrack(y=y, sr=sr, hop_length=hop)
    pitch = np.mean(pitches[pitches > 0]) if np.any(pitches > 0) else 0

    features = np.hstack([mfcc_mean, spectral_centroid, spectral_rolloff, zero_crossing_rate, pitch])
    return features

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

    # Convert to WAV if needed
    ext = filename.split('.')[-1].lower()
    if ext in ["mp3", "m4a", "aac"]:
        sound = AudioSegment.from_file(temp_path, format=ext)
        wav_path = temp_path.rsplit(".", 1)[0] + ".wav"
        sound.export(wav_path, format="wav")
        os.remove(temp_path)
        temp_path = wav_path

    try:
        features = extract_features_from_squeaks(temp_path)
        if features is None:
            return jsonify({"error": "No duckling squeak detected"}), 200

        features_scaled = scaler.transform([features])
        raw_probs = model.predict_proba(features_scaled)[0]
        probs = sharpen_probabilities(raw_probs)

        pred = model.classes_[np.argmax(probs)]
        conf = float(np.max(probs) * 100)

        # Encode WAV as Base64 for Flutter
        with open(temp_path, "rb") as f:
            wav_base64 = base64.b64encode(f.read()).decode("utf-8")

        return jsonify({
            "prediction": pred,
            "confidence": round(conf, 2),
            "wav_base64": wav_base64
        })

    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)

# -------------------------------
# 🔥 RUN SERVER
# -------------------------------
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
