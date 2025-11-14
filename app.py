import os
import numpy as np
import librosa
from flask import Flask, request, jsonify
import joblib
from pydub import AudioSegment
from io import BytesIO
from werkzeug.utils import secure_filename

app = Flask(__name__)

# Load model and scaler
model = joblib.load("duckling_svm_rbf_day4-13.pkl")
scaler = joblib.load("duckling_scaler_day4-13.pkl")

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
    energy_th = np.percentile(energy, 70)
    freq_th = 3800  # Duckling squeaks: 4k–12k Hz
    valid = (energy > energy_th) & (centroid > freq_th)
    return valid

# -------------------------------
# 🔥 MAIN FEATURE EXTRACTION
# -------------------------------
def extract_squeak_features(y, sr):
    valid_frames = detect_squeak_frames(y, sr)
    if not np.any(valid_frames):
        return None
    mfcc = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=20)
    squeak_mfcc = mfcc[:, valid_frames]
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
    ext = filename.lower().split(".")[-1]

    # Read file into memory
    audio_bytes = BytesIO(audio_file.read())

    # Convert to WAV in memory if needed
    if ext in ["mp3", "m4a"]:
        sound = AudioSegment.from_file(audio_bytes, format=ext)
        wav_bytes = BytesIO()
        sound.export(wav_bytes, format="wav")
        wav_bytes.seek(0)
    else:
        wav_bytes = audio_bytes
        wav_bytes.seek(0)

    # Load audio with librosa directly from memory
    y, sr = librosa.load(wav_bytes, sr=None)
    y = librosa.util.normalize(y)

    # Extract features
    features = extract_squeak_features(y, sr)
    if features is None:
        return jsonify({"error": "No duckling squeak detected"}), 200

    # Scale + predict
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

# -------------------------------
# 🔥 RUN SERVER
# -------------------------------
if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))  # Render port
    app.run(host="0.0.0.0", port=port)
