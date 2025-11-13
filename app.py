# try.py (Flask API - optimized to match trainer)
# --- install these first ---
# pip install flask librosa numpy joblib pydub pandas soundfile

from flask import Flask, request, jsonify
import librosa, numpy as np, joblib, os, uuid, traceback, pandas as pd
from werkzeug.utils import secure_filename
from pydub import AudioSegment, silence
import warnings
import gc
import os

warnings.filterwarnings("ignore")

app = Flask(__name__)

# --- Load model and scaler ---
MODEL_PATH = "duckling_svm_rbf_day4-13.pkl"
SCALER_PATH = "duckling_scaler_day4-13.pkl"

model = joblib.load(MODEL_PATH)
scaler = joblib.load(SCALER_PATH)
print("Model and scaler loaded successfully!")

# --- Feature extraction ---
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

# --- Clean and split audio ---
def preprocess_audio(file_path, clip_length_ms=3000, min_silence_len=500, silence_thresh=-45):
    os.makedirs("temp", exist_ok=True)
    audio = AudioSegment.from_file(file_path)
    chunks = silence.split_on_silence(audio, min_silence_len=min_silence_len, silence_thresh=silence_thresh)

    if not chunks:
        chunks = [audio]

    combined = AudioSegment.empty()
    for c in chunks:
        combined += c + AudioSegment.silent(duration=100)

    clip_paths = []
    for i, start in enumerate(range(0, len(combined), clip_length_ms)):
        clip = combined[start:start + clip_length_ms]
        if len(clip) > 1000:
            clip_path = os.path.join("temp", f"clip_{uuid.uuid4().hex}.wav")
            clip.export(clip_path, format="wav")
            clip_paths.append(clip_path)
    return clip_paths

# --- Process a single clip ---
def process_clip(clip_path):
    features = extract_features(clip_path).reshape(1, -1)
    cols = [f"mfcc{i+1}" for i in range(13)] + ["spectral_centroid", "spectral_rolloff", "zero_crossing_rate", "pitch"]
    features_df = pd.DataFrame(features, columns=cols)
    features_scaled = scaler.transform(features_df)
    probs = model.predict_proba(features_scaled)[0]
    return probs

# --- Status endpoint ---
@app.route("/status", methods=["GET"])
def status():
    return jsonify({"status": "ready"}), 200

# --- Prediction endpoint ---
@app.route("/predict", methods=["POST"])
def predict():
    if "file" not in request.files:
        return jsonify({"error": "No file uploaded"}), 400

    file = request.files["file"]
    if file.filename == "":
        return jsonify({"error": "Empty filename"}), 400

    os.makedirs("temp", exist_ok=True)
    orig_path = os.path.join("temp", secure_filename(file.filename))
    file.save(orig_path)

    try:
        # Convert to mono 16kHz WAV
        audio = AudioSegment.from_file(orig_path)
        audio = audio.set_channels(1).set_frame_rate(16000)
        converted_path = os.path.join("temp", f"{uuid.uuid4().hex}_converted.wav")
        audio.export(converted_path, format="wav")

        # Preprocess and split
        clips = preprocess_audio(converted_path)

        if not clips:
            raise ValueError("No valid clips after preprocessing")

        # Sequential prediction (low memory)
        all_probs = []
        for clip_path in clips:
            probs = process_clip(clip_path)
            all_probs.append(probs)
            os.remove(clip_path)  # free memory

        # Average probabilities
        avg_probs = np.mean(all_probs, axis=0)
        max_idx = int(np.argmax(avg_probs))
        pred_class = model.classes_[max_idx]
        gender = "Male" if "male" in pred_class.lower() else "Female"
        confidence_val = float(avg_probs[max_idx])

        # Per-class confidence
        confidence_male = float(avg_probs[model.classes_.tolist().index("male")]) * 100 if "male" in model.classes_ else 0.0
        confidence_female = float(avg_probs[model.classes_.tolist().index("female")]) * 100 if "female" in model.classes_ else 0.0

        return jsonify({
            "prediction": gender.capitalize(),
            "confidence": round(confidence_val * 100, 2),
            "confidence_male": round(confidence_male, 2),
            "confidence_female": round(confidence_female, 2)
        })

    except Exception as e:
        print("Prediction error:", e)
        print(traceback.format_exc())
        return jsonify({"error": str(e), "trace": traceback.format_exc()}), 500

    finally:
        # Cleanup
        for path in [orig_path, converted_path]:
            if path and os.path.exists(path):
                os.remove(path)
        gc.collect()


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port, debug=True)

