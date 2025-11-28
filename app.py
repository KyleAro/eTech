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
    print("🔄 Warming up server...")
    try:
        model = joblib.load("duckling_svm_rbf_day4-13.pkl")
        scaler = joblib.load("duckling_scaler_day4-13.pkl")
        server_ready = True
        print("✅ Server ready!")
        print(f"📊 Model classes: {model.classes_}")
    except Exception as e:
        print(f"❌ Error loading model: {e}")
        server_ready = False

# Start warm-up in a separate thread so Render responds immediately
threading.Thread(target=warm_up).start()

# === FEATURE EXTRACTION ===
def extract_features(audio_bytes):
    """Extract audio features for model prediction"""
    try:
        y, sr = librosa.load(io.BytesIO(audio_bytes), sr=None)
        y = librosa.util.normalize(y)

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

# === SPLIT AUDIO ON SILENCE & CLIP ===
def split_audio(file_bytes):
    """Split audio into clips based on silence detection"""
    try:
        audio = AudioSegment.from_file(io.BytesIO(file_bytes))
        chunks = silence.split_on_silence(
            audio, 
            min_silence_len=MIN_SILENCE_LEN, 
            silence_thresh=SILENCE_THRESH
        )

        combined = AudioSegment.empty()
        for c in chunks:
            combined += c + AudioSegment.silent(duration=100)

        clips = []
        for start in range(0, len(combined), CLIP_LENGTH_MS):
            clip = combined[start:start + CLIP_LENGTH_MS]
            if len(clip) > 1000:  # Only include clips longer than 1 second
                buf = io.BytesIO()
                clip.export(buf, format="wav")
                clips.append(buf.getvalue())
        
        print(f"🎵 Generated {len(clips)} clips from audio")
        return clips
    except Exception as e:
        print(f"❌ Audio splitting error: {e}")
        raise

# === NORMALIZE PREDICTION TO TITLE CASE ===
def normalize_prediction(pred):
    """Normalize prediction to Title Case (Male/Female)"""
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
    """Main prediction endpoint"""
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
        # Read and process file
        file_bytes = request.files["file"].read()
        
        if len(file_bytes) == 0:
            return jsonify({
                "status": "error", 
                "message": "Empty file uploaded"
            }), 400
        
        print(f"📁 Received file: {len(file_bytes)} bytes")
        
        # Split audio into clips
        clips = split_audio(file_bytes)

        if not clips or len(clips) == 0:
            return jsonify({
                "status": "error", 
                "message": "Audio too short or silent - no valid clips generated"
            }), 400

        # Prepare feature columns
        cols = [f"mfcc{i+1}" for i in range(13)] + [
            "spectral_centroid", 
            "spectral_rolloff", 
            "zero_crossing_rate", 
            "pitch"
        ]

        # Predict each clip
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
                conf = float(max(prob) * 100)  # Explicit float conversion
                
                # Normalize to Title Case
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

        # Calculate summary statistics
        summary_counter = Counter(all_predictions)
        majority_pred = max(summary_counter, key=summary_counter.get)
        avg_conf = float(np.mean(all_confidences))

        # Build response with explicit type conversions
        response_data = {
            "status": "success",
            "final_prediction": majority_pred,  # Already Title Case
            "average_confidence": round(avg_conf, 2),
            "total_clips": int(len(clips)),
            "male_clips": int(summary_counter.get("Male", 0)),
            "female_clips": int(summary_counter.get("Female", 0)),
            "prediction_summary": clip_results
        }
        
        print(f"✅ Prediction complete: {majority_pred} ({avg_conf:.2f}%)")
        print(f"📊 Breakdown: {summary_counter}")
        
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
    """Health check endpoint"""
    return jsonify({
        "status": "ready" if server_ready else "warming_up",
        "model_loaded": model is not None,
        "scaler_loaded": scaler is not None
    }), 200

@app.route("/test", methods=["GET"])
def test():
    """Test endpoint to verify model configuration"""
    if not server_ready:
        return jsonify({
            "status": "not_ready",
            "message": "Server still warming up"
        }), 503
    
    return jsonify({
        "status": "ready",
        "model_classes": model.classes_.tolist() if model else [],
        "sample_responses": {
            "male": normalize_prediction("male"),
            "female": normalize_prediction("female"),
            "MALE": normalize_prediction("MALE"),
        },
        "type_examples": {
            "int_example": int(5),
            "float_example": float(95.5),
            "string_example": "Male"
        }
    }), 200

@app.route("/", methods=["GET"])
def home():
    """Root endpoint"""
    return jsonify({
        "message": "Gender Prediction API",
        "status": "ready" if server_ready else "warming_up",
        "endpoints": {
            "/predict": "POST - Upload audio file for prediction",
            "/status": "GET - Check server status",
            "/test": "GET - Test model configuration"
        }
    }), 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000, debug=False)