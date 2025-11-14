import os
import numpy as np
import librosa
from flask import Flask, request, jsonify
import joblib
from pydub import AudioSegment
from werkzeug.utils import secure_filename
import base64
import tempfile

app = Flask(__name__)

# -------------------------------
# 🔥 LOAD MODEL & SCALER
# -------------------------------
model = joblib.load("duckling_svm_rbf_day4-13.pkl")
scaler = joblib.load("duckling_scaler_day4-13.pkl")

UPLOAD_FOLDER = "uploads"
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

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
    freq_th = 3800
    valid = (energy > energy_th) & (centroid > freq_th)
    return valid

def extract_squeak_features(file_path):
    y, sr = librosa.load(file_path, sr=None)
    y = librosa.util.normalize(y)
    hop = 256
    valid_frames = detect_squeak_frames(y, sr, hop=hop)
    if not np.any(valid_frames):
        return None
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
    except Exception as e:
        return jsonify({"status": f"Server error: {str(e)}"}), 503

# -------------------------------
# 🔥 PREDICT ENDPOINT
# -------------------------------
@app.route("/predict", methods=["POST"])
def predict():
    import tempfile
    import os
    import base64
    from werkzeug.utils import secure_filename
    from pydub import AudioSegment

    # ------------------------------
    # Determine audio source
    # ------------------------------
    audio_file = request.files.get("audio")
    audio_base64 = request.json.get("audio_base64") if request.is_json else None

    if not audio_file and not audio_base64:
        return jsonify({"error": "No audio provided"}), 400

    # Save audio to temp file
    if audio_file:
        filename = secure_filename(audio_file.filename)
        temp_path = os.path.join(tempfile.gettempdir(), filename)
        audio_file.save(temp_path)
    else:
        filename = "recorded.wav"
        temp_path = os.path.join(tempfile.gettempdir(), filename)
        with open(temp_path, "wb") as f:
            f.write(base64.b64decode(audio_base64))

    # Convert to WAV if needed
    ext = filename.split('.')[-1].lower()
    if ext in ["m4a", "mp3", "aac"]:
        sound = AudioSegment.from_file(temp_path, format=ext)
        wav_path = temp_path.rsplit(".", 1)[0] + ".wav"
        sound.export(wav_path, format="wav")
        os.remove(temp_path)
        temp_path = wav_path

    try:
        # Extract features, predict, encode WAV
        features = extract_squeak_features(temp_path)
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
            "wav_base64": wav_base64,
        })
    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)
# -------------------------------
# 🔥 RUN SERVER
# -------------------------------
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
