from flask import Flask, request, jsonify
import os
import librosa
import numpy as np
import pandas as pd
from pydub import AudioSegment, silence
import joblib
from collections import Counter
import tempfile
import shutil

# === LOAD MODEL & SCALER ===
model = joblib.load("duckling_svm_rbf_day4-13.pkl")
scaler = joblib.load("duckling_scaler_day4-13.pkl")

# === SETTINGS ===
CLIP_LENGTH_MS = 3000
MIN_SILENCE_LEN = 500
SILENCE_THRESH = -45

app = Flask(__name__)


# === FEATURE EXTRACTION ===
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


# === PROCESS AUDIO (remove silence + split) ===
def preprocess_audio(file_path):
    temp_dir = tempfile.mkdtemp()
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
    for i, start in enumerate(range(0, len(combined), CLIP_LENGTH_MS)):
        clip = combined[start:start + CLIP_LENGTH_MS]
        if len(clip) > 1000:
            clip_path = os.path.join(temp_dir, f"clip_{i+1}.wav")
            clip.export(clip_path, format="wav")
            clip_paths.append(clip_path)

    return clip_paths, temp_dir


@app.route("/predict", methods=["POST"])
def predict():
    if "file" not in request.files:
        return jsonify({"error": "No file uploaded"}), 400

    uploaded_file = request.files["file"]

    # ⬇️ Save temp input file
    temp_input = tempfile.NamedTemporaryFile(delete=False, suffix=".wav")
    uploaded_file.save(temp_input.name)

    try:
        # 1️⃣ Preprocess + segment audio
        clips, temp_dir = preprocess_audio(temp_input.name)
        if len(clips) == 0:
            return jsonify({"error": "No valid audio found"}), 400

        cols = [f"mfcc{i+1}" for i in range(13)] + \
               ["spectral_centroid", "spectral_rolloff", "zero_crossing_rate", "pitch"]

        predictions = []
        confidences = []

        # 2️⃣ Predict all clips
        for clip_path in clips:
            features = extract_features(clip_path).reshape(1, -1)
            df = pd.DataFrame(features, columns=cols)
            scaled = scaler.transform(df)

            prob = model.predict_proba(scaled)[0]
            pred = model.classes_[np.argmax(prob)]
            conf = float(np.max(prob)) * 100

            predictions.append(pred)
            confidences.append(conf)

        # 3️⃣ Final Result (Majority Vote)
        summary = Counter(predictions)
        final_prediction = max(summary, key=summary.get)
        final_confidence = float(np.mean(confidences))

        return jsonify({
            "prediction": final_prediction,
            "confidence": final_confidence
        })

    except Exception as e:
        return jsonify({"error": str(e)}), 500

    finally:
        try:
            shutil.rmtree(temp_dir)
        except:
            pass
        try:
            os.remove(temp_input.name)
        except:
            pass


@app.route("/", methods=["GET"])
def home():
    return "Duckling Gender Classifier API is running."


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
