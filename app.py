import os
import numpy as np
import librosa
from flask import Flask, request, jsonify
import joblib
from pydub import AudioSegment
from werkzeug.utils import secure_filename

app = Flask(__name__)

# -------------------------------
# 🔥 LOAD MODEL & SCALER
# -------------------------------
model = joblib.load("duckling_svm_rbf_day4-13.pkl")
scaler = joblib.load("duckling_scaler_day4-13.pkl")

UPLOAD_FOLDER = "uploads"
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

# -------------------------------
# 🔥 HELPER: Probability Sharpening
# -------------------------------
def sharpen_probabilities(p, temp=0.35):
    p = np.power(p, 1 / temp)
    p /= np.sum(p)
    return p

# -------------------------------
# 🔥 HELPER: Detect Duckling Squeak Frames
# -------------------------------
def detect_squeak_frames(y, sr):
    hop = 256
    win = 512

    energy = librosa.feature.rms(y=y, frame_length=win, hop_length=hop)[0]
    centroid = librosa.feature.spectral_centroid(y=y, sr=sr, hop_length=hop)[0]

    energy_th = np.percentile(energy, 70)
    freq_th = 3800  # duckling squeaks: ~4k–12k Hz

    valid = (energy > energy_th) & (centroid > freq_th)
    return valid

# -------------------------------
# 🔥 FEATURE EXTRACTION
# -------------------------------
def extract_squeak_features(file_path):
    y, sr = librosa.load(file_path, sr=None)
    y = librosa.util.normalize(y)

    # Detect squeak frames
    valid_frames = detect_squeak_frames(y, sr)
    if not np.any(valid_frames):
        return None  # No duckling squeak detected

    # --- MFCCs (13) ---
    mfcc = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=13)
    squeak_mfcc = mfcc[:, valid_frames]
    mfcc_mean = np.mean(squeak_mfcc, axis=1)

    # --- Spectral features ---
    spectral_centroid = np.mean(librosa.feature.spectral_centroid(y=y, sr=sr))
    spectral_rolloff = np.mean(librosa.feature.spectral_rolloff(y=y, sr=sr))
    zero_crossing_rate = np.mean(librosa.feature.zero_crossing_rate(y))

    # --- Pitch ---
    pitches, magnitudes = librosa.piptrack(y=y, sr=sr)
    pitch = np.mean(pitches[pitches > 0]) if np.any(pitches > 0) else 0

    # Combine into single feature vector (17 features total)
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
    except FileNotFoundError:
        return jsonify({"status": "Required files not found"}), 404
    except Exception as e:
        return jsonify({"status": f"Server error: {str(e)}"}), 503

# -------------------------------
# 🔥 PREDICT ENDPOINT
# -------------------------------
@app.route("/predict", methods=["POST"])
def predict():
    if "audio" not in request.files:
        return jsonify({"error": "No audio uploaded"}), 400

    audio_file = request.files["audio"]
    filename = secure_filename(audio_file.filename)
    filepath = os.path.join(UPLOAD_FOLDER, filename)
    audio_file.save(filepath)

    # Convert to WAV if necessary
    ext = filename.lower().split(".")[-1]
    if ext in ["m4a", "mp3"]:
        sound = AudioSegment.from_file(filepath, format=ext)
        filepath = filepath.replace(f".{ext}", ".wav")
        sound.export(filepath, format="wav")

    # Extract features
    features = extract_squeak_features(filepath)
    if features is None:
        return jsonify({"error": "No duckling squeak detected"}), 200

    # Scale + Predict
    features_scaled = scaler.transform([features])
    raw_probs = model.predict_proba(features_scaled)[0]
    probs = sharpen_probabilities(raw_probs, temp=0.35)

    pred = model.classes_[np.argmax(probs)]
    conf = float(np.max(probs) * 100)

    return jsonify({
        "prediction": pred,
        "confidence": round(conf, 2),
        "raw_probabilities": raw_probs.tolist(),
        "sharpened_probabilities": probs.tolist()
    })


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
