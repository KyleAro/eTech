import os
import shutil
import tempfile
from collections import Counter

import joblib
import librosa
import numpy as np
import pandas as pd
from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydub import AudioSegment, silence

# === LOAD MODEL & SCALER ===
model = joblib.load("duckling_svm_rbf_day4-13.pkl")
scaler = joblib.load("duckling_scaler_day4-13.pkl")

# === SETTINGS ===
CLIP_LENGTH_MS = 3000
MIN_SILENCE_LEN = 500
SILENCE_THRESH = -45

app = FastAPI(title="Duckling Gender Classifier API")

# Allow Flutter app to call API
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # change to your prod domain if needed
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


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


# === PROCESS AUDIO (remove silence + segment) ===
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
            clip_path = os.path.join(temp_dir, f"clip_{i + 1}.wav")
            clip.export(clip_path, format="wav")
            clip_paths.append(clip_path)

    return clip_paths, temp_dir


@app.post("/predict")
async def predict_audio(file: UploadFile = File(...)):
    if file is None:
        raise HTTPException(status_code=400, detail="No file uploaded")

    # Save uploaded temp file
    temp_input = tempfile.NamedTemporaryFile(delete=False, suffix=file.filename[-4:])
    temp_input.write(await file.read())
    temp_input.close()

    try:
        # 1️⃣ Preprocess audio → silence removal + splitting
        clips, temp_dir = preprocess_audio(temp_input.name)
        if len(clips) == 0:
            raise HTTPException(status_code=400, detail="No valid audio found")

        cols = [f"mfcc{i+1}" for i in range(13)] + \
               ["spectral_centroid", "spectral_rolloff", "zero_crossing_rate", "pitch"]

        predictions = []
        confidences = []

        # 2️⃣ Predict each clip
        for clip_path in clips:
            features = extract_features(clip_path).reshape(1, -1)
            df = pd.DataFrame(features, columns=cols)
            scaled = scaler.transform(df)

            prob = model.predict_proba(scaled)[0]
            pred = model.classes_[np.argmax(prob)]
            conf = float(np.max(prob)) * 100

            predictions.append(pred)
            confidences.append(conf)

        # 3️⃣ Majority vote
        summary = Counter(predictions)
        final_prediction = max(summary, key=summary.get)
        final_confidence = float(np.mean(confidences))

        return {
            "prediction": final_prediction,
            "confidence": final_confidence
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    finally:
        try:
            shutil.rmtree(temp_dir)
        except:
            pass
        try:
            os.remove(temp_input.name)
        except:
            pass


@app.get("/")
def home():
    return {"status": "Duckling Gender Classifier API (FastAPI) is running!"}
