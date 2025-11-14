import os
import numpy as np
import librosa
from flask import Flask, request, jsonify
import joblib
from pydub import AudioSegment
from werkzeug.utils import secure_filename
import base64

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
    """Increase confidence by sharpening probabilities."""
    p = np.power(p, 1 / temp)
    p /= np.sum(p)
    return p

# -------------------------------
# 🔥 HELPER: Detect Duckling Squeak Frames
# -------------------------------
def detect_squeak_frames(y, sr, hop=256, win=512):
    """Return a boolean mask for frames containing duckling squeaks."""
    energy = librosa.feature.rms(y=y, frame_length=win, hop_length=hop)[0]
    centroid = librosa.feature.spectral_centroid(y=y, sr=sr, hop_length=hop)[0]

    energy_th = np.percentile(energy, 70)
    freq_th = 3800  # duckling squeaks are high-pitched

    valid = (energy > energy_th) & (centroid > freq_th)
    return valid

# -------------------------------
# 🔥 HELPER: Feature Extraction
# -------------------------------
def extract_squeak_features(file_path):
    y, sr = librosa.load(file_path, sr=None)
    y = librosa.util.normalize(y)

    hop = 256  # frame hop consistent across features
    valid_frames = detect_squeak_frames(y, sr, hop=hop)
    if not np.any(valid_frames):
        return None

    # MFCCs (13) for squeaky frames
    mfcc = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=13, hop_length=hop)
    squeak_mfcc = mfcc[:, valid_frames]
    mfcc_mean = np.mean(squeak_mfcc, axis=1)

    # Spectral features
    spectral_centroid = np.mean(librosa.feature.spectral_centroid(y=y, sr=sr, hop_length=hop))
    spectral_rolloff = np.mean(librosa.feature.spectral_rolloff(y=y, sr=sr, hop_length=hop))
    zero_crossing_rate = np.mean(librosa.feature.zero_crossing_rate(y, hop_length=hop))

    # Pitch
    pitches, magnitudes = librosa.piptrack(y=y, sr=sr, hop_length=hop)
    pitch = np.mean(pitches[pitches > 0]) if np.any(pitches > 0) else 0

    # Combine all 17 features
    features = np.hstack([mfcc_mean, spectral_centroid, spectral_rolloff, zero_crossing_rate, pitch])
    return features
# -------------------------------
# 🔥 HELPER: Extract waveform
# -------------------------------
def extract_waveform(file_path, target_length=1000):
    y, sr = librosa.load(file_path, sr=None)
    y = librosa.util.normalize(y)

    if len(y) > target_length:
        factor = len(y) // target_length
        y_down = y[::factor]
    else:
        y_down = y

    return y_down.tolist()

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

    # Convert to WAV if needed
    ext = filename.lower().split(".")[-1]
    if ext in ["m4a", "mp3"]:
        sound = AudioSegment.from_file(filepath, format=ext)
        filepath = filepath.replace(f".{ext}", ".wav")
        sound.export(filepath, format="wav")

    # Extract features
    features = extract_squeak_features(filepath)
    if features is None:
        return jsonify({"error": "No duckling squeak detected"}), 200

    # Scale + predict
    features_scaled = scaler.transform([features])
    raw_probs = model.predict_proba(features_scaled)[0]
    probs = sharpen_probabilities(raw_probs, temp=0.35)

    pred = model.classes_[np.argmax(probs)]
    conf = float(np.max(probs) * 100)
    waveform = extract_waveform(filepath, target_length=1000)
    # Encode WAV file as Base64
    with open(filepath, "rb") as f:
        wav_bytes = f.read()
    wav_base64 = base64.b64encode(wav_bytes).decode("utf-8")

    return jsonify({
        "prediction": pred,
        "confidence": round(conf, 2),
        "raw_probabilities": raw_probs.tolist(),
        "sharpened_probabilities": probs.tolist(),
        "waveform": waveform,
        "wav_base64": wav_base64,
    })

# -------------------------------
# 🔥 RUN SERVER
# -------------------------------
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
