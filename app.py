# --- INSTALL THESE FIRST ---
# pip install flask librosa pydub numpy pandas scikit-learn joblib

from flask import Flask, request, jsonify
from pydub import AudioSegment, silence
import numpy as np
import pandas as pd
import librosa
import joblib
from collections import Counter
import io
import threading

# === SETTINGS ===
CLIP_LENGTH_MS = 3000
MIN_SILENCE_LEN = 500
SILENCE_THRESH = -45

# === LOAD MODEL & SCALER (WARM-UP) ===
model = None
scaler = None
server_ready = False

def warm_up():
    global model, scaler, server_ready
    print("Warming up server...")
    model = joblib.load("duckling_svm_rbf_day4-13.pkl")
    scaler = joblib.load("duckling_scaler_day4-13.pkl")
    server_ready = True
    print("Server ready!")

# Start warm-up in a separate thread so Render responds immediately
threading.Thread(target=warm_up).start()

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

# === SPLIT AUDIO ON SILENCE & CLIP ===
def split_audio(file_bytes):
    # Create AudioSegment directly from raw PCM16 bytes
    audio = AudioSegment(
        data=file_bytes,
        sample_width=2,       # 16-bit PCM
        frame_rate=16000,     # 16kHz (must match Flutter recording)
        channels=1            # mono (must match Flutter recording)
    )

    chunks = silence.split_on_silence(audio, min_silence_len=MIN_SILENCE_LEN, silence_thresh=SILENCE_THRESH)

    combined = AudioSegment.empty()
    for c in chunks:
        combined += c + AudioSegment.silent(duration=100)

    clips = []
    for start in range(0, len(combined), CLIP_LENGTH_MS):
        clip = combined[start:start + CLIP_LENGTH_MS]
        if len(clip) > 1000:
            buf = io.BytesIO()
            clip.export(buf, format="wav")  # Keep WAV for librosa
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

    summary = Counter(predictions)
    majority_pred = max(summary, key=summary.get)
    avg_conf = round(np.mean(confidences), 2)

    return majority_pred, avg_conf

# === FLASK APP ===
app = Flask(__name__)

@app.route("/predict", methods=["POST"])
def predict():
    if not server_ready:
        return jsonify({"status": "error", "message": "Server warming up, try again in a few seconds"}), 503

    if "file" not in request.files:
        return jsonify({"status": "error", "message": "No file uploaded"}), 400

    file_bytes = request.files["file"].read()
    clips = split_audio(file_bytes)

    if not clips:
        return jsonify({"status": "error", "message": "Audio too short or silent"}), 400

    prediction, confidence = predict_clips(clips)
    if prediction is None:
        return jsonify({"status": "error", "message": "Could not make prediction"}), 500

    return jsonify({"status": "success", "prediction": prediction, "confidence": confidence})

# === SERVER STATUS ENDPOINT ===
@app.route("/status", methods=["GET"])
def status():
    return jsonify({"status": "ready" if server_ready else "warming_up"})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)