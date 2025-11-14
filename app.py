import os
import numpy as np
import librosa
from flask import Flask, request, jsonify
import joblib
from pydub import AudioSegment
from werkzeug.utils import secure_filename

app = Flask(__name__)

model = joblib.load("duckling_svm_rbf_day4-13.pkl")
scaler = joblib.load("duckling_scaler_day4-13.pkl")

UPLOAD_FOLDER = "uploads"
os.makedirs(UPLOAD_FOLDER, exist_ok=True)


# -------------------------------
# 🔥 HELPER: Probability Sharpening
# -------------------------------
def sharpen_probabilities(p, temp=0.35):
    """Increase confidence by sharpening probabilities."""
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

    # Duckling squeaks are LOUD + HIGH FREQUENCY
    energy_th = np.percentile(energy, 70)
    freq_th = 3800  # ducklings squeaks: 4k–12k Hz

    valid = (energy > energy_th) & (centroid > freq_th)

    return valid


# -------------------------------
# 🔥 MAIN FEATURE EXTRACTION
# -------------------------------
def extract_squeak_features(file_path):
    y, sr = librosa.load(file_path, sr=None)
    y = librosa.util.normalize(y)

    valid_frames = detect_squeak_frames(y, sr)

    if not np.any(valid_frames):
        return None  # No squeak detected

    # Use only the frames where squeaks exist
    mfcc = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=20)
    squeak_mfcc = mfcc[:, valid_frames]

    # Single feature vector (mean of squeaky frames)
    features = np.mean(squeak_mfcc, axis=1)

    return features


# -------------------------------
# 🔥 API ENDPOINT
# -------------------------------
@app.route("/predict", methods=["POST"])
def predict():
    if "audio" not in request.files:
        return jsonify({"error": "No audio uploaded"}), 400

    audio_file = request.files["audio"]
    filename = secure_filename(audio_file.filename)
    filepath = os.path.join(UPLOAD_FOLDER, filename)
    audio_file.save(filepath)

    # Convert to WAV if M4A/MP3
    ext = filename.lower().split(".")[-1]
    if ext in ["m4a", "mp3"]:
        sound = AudioSegment.from_file(filepath, format=ext)
        filepath = filepath.replace(f".{ext}", ".wav")
        sound.export(filepath, format="wav")

    # Extract DUCKLING squeak features
    features = extract_squeak_features(filepath)

    if features is None:
        return jsonify({"error": "No duckling squeak detected"}), 200

    # Scale + Predict
    features_scaled = scaler.transform([features])
    raw_probs = model.predict_proba(features_scaled)[0]

    # Sharpen probabilities (boost confidence)
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
