# --- INSTALL THESE FIRST ---
# pip install flask librosa pydub numpy pandas scikit-learn joblib soundfile scipy noisereduce

from flask import Flask, request, jsonify
from pydub import AudioSegment, silence
import numpy as np
import pandas as pd
import librosa
import joblib
from collections import Counter
import io
import base64
import threading
import soundfile as sf

# === NEW: shared cleaning module ===
# This is the single source of truth for audio cleaning. Training (ML_Train.py)
# uses the same function — without that parity, accuracy drops silently.
from audio_clean import clean_audio, clean_audio_to_wav_bytes, TARGET_SR

# === SETTINGS ===
CLIP_LENGTH_MS = 3000
MIN_SILENCE_LEN = 500
SILENCE_THRESH = -45

# === LOAD MODEL & SCALER (WARM-UP) ===
# IMPORTANT: filenames bumped to *_cleaned.pkl. Make sure to retrain
# (run ML_Train.py) and upload the new .pkl files to your Render volume,
# otherwise the SVM is making predictions on cleaned features it never
# learned from.
model = None
scaler = None
server_ready = False


def warm_up():
    global model, scaler, server_ready
    print("🔄 Warming up server...")
    try:
        model = joblib.load("duckling_svm_rbf_cleaned.pkl")
        scaler = joblib.load("duckling_scaler_cleaned.pkl")
        server_ready = True
        print("✅ Server ready!")
        print(f"📊 Model classes: {model.classes_}")
    except Exception as e:
        print(f"❌ Error loading model: {e}")
        server_ready = False


# Start warm-up in a separate thread so Render responds immediately
threading.Thread(target=warm_up).start()


# === FEATURE EXTRACTION ===
# Operates on already-cleaned WAV bytes (split_audio passes cleaned clips).
# We still call librosa.load here to pick up the bytes, but no second
# cleaning pass — the data was cleaned upstream once for the whole recording.
def extract_features(audio_bytes):
    """Extract audio features for model prediction (input: cleaned WAV bytes)."""
    try:
        y, sr = librosa.load(io.BytesIO(audio_bytes), sr=None)
        # NOTE: removed librosa.util.normalize(y) — clean_audio() already
        # peak-normalized the parent recording. Re-normalizing each clip
        # would erase loudness differences between clips.

        mfccs = np.mean(librosa.feature.mfcc(y=y, sr=sr, n_mfcc=13).T, axis=0)
        spectral_centroid = np.mean(librosa.feature.spectral_centroid(y=y, sr=sr))
        spectral_rolloff = np.mean(librosa.feature.spectral_rolloff(y=y, sr=sr))
        zero_crossing_rate = np.mean(librosa.feature.zero_crossing_rate(y))
        pitches, magnitudes = librosa.piptrack(y=y, sr=sr)
        pitch = np.mean(pitches[pitches > 0]) if np.any(pitches > 0) else 0

        return np.hstack([mfccs, spectral_centroid, spectral_rolloff, zero_crossing_rate, pitch])
    except Exception as e:
        print(f"❌ Feature extraction error: {e}")
        raise


# === CLEAN + SPLIT ===
def clean_and_split(file_bytes):
    """Run the full cleaning pipeline, then split into clips.

    Returns
    -------
    clips : list[bytes]    — WAV-encoded 3-second clips, already cleaned.
    cleaned_wav : bytes    — full cleaned recording, WAV-encoded.
                              Sent back to the client so the user can hear it.
    """
    try:
        # 1. CLEAN. clean_audio_to_wav_bytes accepts raw bytes and returns
        # cleaned WAV bytes + sample rate. Internally: HPF + LPF + spectral
        # gate + peak-normalize + silence-trim.
        print("🧼 Cleaning audio with duckling-tuned DSP pipeline...")
        cleaned_wav, sr = clean_audio_to_wav_bytes(file_bytes)
        print(f"✅ Cleaned ({len(cleaned_wav)} bytes @ {sr}Hz)")

        # 2. Load cleaned WAV into pydub for silence-aware splitting.
        audio = AudioSegment.from_file(io.BytesIO(cleaned_wav))
        chunks = silence.split_on_silence(
            audio,
            min_silence_len=MIN_SILENCE_LEN,
            silence_thresh=SILENCE_THRESH
        )

        combined = AudioSegment.empty()
        for c in chunks:
            combined += c + AudioSegment.silent(duration=100)

        # 3. Cut into fixed 3-second clips.
        clips = []
        for start in range(0, len(combined), CLIP_LENGTH_MS):
            clip = combined[start:start + CLIP_LENGTH_MS]
            if len(clip) > 1000:
                buf = io.BytesIO()
                clip.export(buf, format="wav")
                clips.append(buf.getvalue())

        print(f"🎵 Generated {len(clips)} clips from cleaned audio")
        return clips, cleaned_wav
    except Exception as e:
        print(f"❌ Clean+split error: {e}")
        raise


# === NORMALIZE PREDICTION TO TITLE CASE ===
def normalize_prediction(pred):
    pred_lower = str(pred).lower().strip()
    if pred_lower == "male":
        return "Male"
    elif pred_lower == "female":
        return "Female"
    else:
        return "Unknown"


# === FLASK APP ===
app = Flask(__name__)


@app.route("/predict", methods=["POST"])
def predict():
    """Main prediction endpoint. Returns prediction + cleaned audio."""
    if not server_ready:
        return jsonify({
            "status": "error",
            "message": "Server warming up, try again in a few seconds"
        }), 503

    if "file" not in request.files:
        return jsonify({
            "status": "error",
            "message": "No file uploaded"
        }), 400

    try:
        file_bytes = request.files["file"].read()

        if len(file_bytes) == 0:
            return jsonify({
                "status": "error",
                "message": "Empty file uploaded"
            }), 400

        print(f"📁 Received file: {len(file_bytes)} bytes")

        # Clean + split (cleaning happens once, here)
        clips, cleaned_wav = clean_and_split(file_bytes)

        if not clips or len(clips) == 0:
            return jsonify({
                "status": "error",
                "message": "Audio too short or silent - no valid clips generated"
            }), 400

        # Feature column layout (must match ML_Train.py exactly)
        cols = [f"mfcc{i+1}" for i in range(13)] + [
            "spectral_centroid",
            "spectral_rolloff",
            "zero_crossing_rate",
            "pitch"
        ]

        clip_results = []
        all_predictions = []
        all_confidences = []

        for idx, clip_bytes in enumerate(clips, 1):
            try:
                features = extract_features(clip_bytes).reshape(1, -1)
                features_df = pd.DataFrame(features, columns=cols)
                features_scaled = scaler.transform(features_df)

                prob = model.predict_proba(features_scaled)[0]
                pred_class = model.classes_[np.argmax(prob)]
                conf = float(max(prob) * 100)

                pred_normalized = normalize_prediction(pred_class)

                clip_results.append({
                    "clip": f"clip_{idx}",
                    "prediction": pred_normalized,
                    "confidence": round(conf, 2)
                })

                all_predictions.append(pred_normalized)
                all_confidences.append(conf)

            except Exception as e:
                print(f"⚠️ Error processing clip {idx}: {e}")
                continue

        if not clip_results:
            return jsonify({
                "status": "error",
                "message": "Failed to process any clips"
            }), 500

        # Summary stats
        summary_counter = Counter(all_predictions)
        majority_pred = max(summary_counter, key=summary_counter.get)
        avg_conf = float(np.mean(all_confidences))

        # Encode cleaned audio for the response.
        # Base64 keeps everything in one JSON payload, which is what Flutter
        # already expects from /predict. Larger payloads but no multipart.
        cleaned_b64 = base64.b64encode(cleaned_wav).decode("ascii")

        response_data = {
            "status": "success",
            "final_prediction": majority_pred,
            "average_confidence": round(avg_conf, 2),
            "total_clips": int(len(clips)),
            "male_clips": int(summary_counter.get("Male", 0)),
            "female_clips": int(summary_counter.get("Female", 0)),
            "prediction_summary": clip_results,
            # NEW: cleaned audio sent back so the user can play what the SVM
            # actually heard. Base64-encoded WAV. Decode on the client.
            "cleaned_audio": {
                "format": "wav",
                "sample_rate": TARGET_SR,
                "base64": cleaned_b64,
                "bytes": len(cleaned_wav),
            },
        }

        print(f"✅ Prediction complete: {majority_pred} ({avg_conf:.2f}%)")
        print(f"📊 Breakdown: {summary_counter}")
        print(f"📦 Cleaned audio attached: {len(cleaned_wav)} bytes")

        return jsonify(response_data), 200

    except Exception as e:
        print(f"❌ Server error: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({
            "status": "error",
            "message": f"Server error: {str(e)}"
        }), 500


@app.route("/status", methods=["GET"])
def status():
    """Health check endpoint."""
    return jsonify({
        "status": "ready" if server_ready else "warming_up",
        "model_loaded": model is not None,
        "scaler_loaded": scaler is not None
    }), 200


@app.route("/test", methods=["GET"])
def test():
    """Test endpoint to verify model configuration."""
    if not server_ready:
        return jsonify({
            "status": "not_ready",
            "message": "Server still warming up"
        }), 503

    return jsonify({
        "status": "ready",
        "model_classes": model.classes_.tolist() if model else [],
        "audio_pipeline": {
            "target_sr": TARGET_SR,
            "cleaning": "HPF 300Hz + LPF 8kHz + spectral gate + peak-norm + trim",
        },
        "sample_responses": {
            "male": normalize_prediction("male"),
            "female": normalize_prediction("female"),
            "MALE": normalize_prediction("MALE"),
        },
    }), 200


@app.route("/", methods=["GET"])
def home():
    """Root endpoint."""
    return jsonify({
        "message": "Gender Prediction API",
        "status": "ready" if server_ready else "warming_up",
        "endpoints": {
            "/predict": "POST - Upload audio, returns prediction + cleaned audio (base64)",
            "/status": "GET - Check server status",
            "/test": "GET - Test model configuration"
        }
    }), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000, debug=False)