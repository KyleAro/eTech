import os
import io
import base64
import numpy as np
import pandas as pd
import librosa
import joblib
import tempfile
import shutil
from pydub import AudioSegment, silence
from collections import Counter
from flask import Flask, request, jsonify

# --- FLASK SETUP ---
app = Flask(__name__)

# --- MODEL & SCALER PATHS ---
# !!! IMPORTANT: Ensure these files are uploaded alongside app.py to Render.
MODEL_PATH = "duckling_svm_rbf_day4-13.pkl"
SCALER_PATH = "duckling_scaler_day4-13.pkl"

# --- GLOBAL VARIABLES ---
model = None
scaler = None

# === SETTINGS (from your original script) ===
CLIP_LENGTH_MS = 3000 # 3 seconds per clip
MIN_SILENCE_LEN = 500
SILENCE_THRESH = -45
# Removed TEMP_CLIPS_DIR - clips are now processed in memory

# === INITIALIZATION AND LOADING ===
def load_models():
    """Load the trained model and scaler globally."""
    global model, scaler
    try:
        if os.path.exists(MODEL_PATH) and os.path.exists(SCALER_PATH):
            model = joblib.load(MODEL_PATH)
            scaler = joblib.load(SCALER_PATH)
            print("✅ Models and scaler loaded successfully.")
        else:
            print(f"❌ Model or scaler file not found at {MODEL_PATH} or {SCALER_PATH}")
            # Exit gracefully if critical files are missing
            raise FileNotFoundError("Required model files missing.")
    except Exception as e:
        print(f"❌ Error loading models: {e}")
        model = None
        scaler = None

# Load models when the application starts
with app.app_context():
    load_models()

# === FEATURE EXTRACTION (Modified to accept raw audio data) ===
def extract_features(y, sr):
    """Extract required features from a single audio time series (y) and sample rate (sr)."""
    # Normalize the time series data
    y = librosa.util.normalize(y.astype(np.float32))

    mfccs = np.mean(librosa.feature.mfcc(y=y, sr=sr, n_mfcc=13).T, axis=0)
    spectral_centroid = np.mean(librosa.feature.spectral_centroid(y=y, sr=sr))
    spectral_rolloff = np.mean(librosa.feature.spectral_rolloff(y=y, sr=sr))
    zero_crossing_rate = np.mean(librosa.feature.zero_crossing_rate(y))
    
    # Pitch features
    pitches, magnitudes = librosa.piptrack(y=y, sr=sr)
    pitch = np.mean(pitches[pitches > 0]) if np.any(pitches > 0) else 0

    return np.hstack([mfccs, spectral_centroid, spectral_rolloff, zero_crossing_rate, pitch])

# === CORE PREDICTION LOGIC ===
def process_and_predict(input_file_path):
    """
    Cleans audio, splits into clips, runs prediction (in memory), and returns results + cleaned WAV bytes path.
    """
    if model is None or scaler is None:
        raise Exception("Model is not loaded. Cannot perform prediction.")

    # 1. Load Audio and Handle Conversion
    ext = os.path.splitext(input_file_path)[1].lower()
    # pydub can handle common formats like mp3, wav, flac
    audio = AudioSegment.from_file(input_file_path, format=ext.replace('.', ''))

    # 2. Split on Silence (Clean)
    chunks = silence.split_on_silence(
        audio,
        min_silence_len=MIN_SILENCE_LEN,
        silence_thresh=SILENCE_THRESH
    )
    combined_cleaned_audio = AudioSegment.empty()
    for c in chunks:
        # Recombine clips with a small gap (100ms)
        combined_cleaned_audio += c + AudioSegment.silent(duration=100)

    # 3. Save the COMBINED, Cleaned Audio as a temporary WAV
    # This file MUST be saved temporarily so we can read its bytes to send back to Dart.
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as temp_wav:
        cleaned_wav_path = temp_wav.name
        combined_cleaned_audio.export(cleaned_wav_path, format="wav")

    # 4. Split the cleaned audio into 3s clips and process IN MEMORY
    audio_duration_ms = len(combined_cleaned_audio)
    clip_data = [] # Stores {'y': numpy array, 'sr': sample rate}

    for start in range(0, audio_duration_ms, CLIP_LENGTH_MS):
        clip = combined_cleaned_audio[start:start + CLIP_LENGTH_MS]
        if len(clip) > 1000: # Only process clips longer than 1 second
            
            # Convert pydub AudioSegment into a NumPy array
            # .get_array_of_samples() extracts the raw audio data
            y_data = np.array(clip.get_array_of_samples())
            sr_data = clip.frame_rate
            
            clip_data.append({'y': y_data, 'sr': sr_data})
    
    if not clip_data:
        # We still return the cleaned WAV, just with 'UNKNOWN' prediction
        return "UNKNOWN", 0.0, cleaned_wav_path


    # 5. Predict Each Clip (using in-memory data)
    cols = [f"mfcc{i+1}" for i in range(13)] + ["spectral_centroid", "spectral_rolloff", "zero_crossing_rate", "pitch"]
    predictions = []
    confidences = []

    for data in clip_data:
        # Call the modified feature extraction function with in-memory data
        features = extract_features(data['y'], data['sr']).reshape(1, -1)
        features_df = pd.DataFrame(features, columns=cols)
        features_scaled = scaler.transform(features_df)

        prob = model.predict_proba(features_scaled)[0]
        pred = model.classes_[np.argmax(prob)]
        confidences.append(max(prob))
        predictions.append(pred)

    # 6. Calculate Final Majority Prediction and Confidence
    summary = Counter(predictions)
    total_clips = len(predictions)
    majority_prediction = max(summary, key=summary.get)
    
    # Calculate majority confidence as the ratio of majority votes to total clips
    majority_confidence = round((summary[majority_prediction] / total_clips) * 100, 2)
    
    # No more shutil.rmtree(TEMP_CLIPS_DIR) needed!
    
    return majority_prediction, majority_confidence, cleaned_wav_path


# === FLASK ROUTES ===

@app.route('/status', methods=['GET'])
def status():
    """Simple status check endpoint for wake-up calls from Dart app."""
    return jsonify({"status": "active", "model_loaded": model is not None}), 200

@app.route('/predict', methods=['POST'])
def predict():
    """Handles audio file upload, processes it, and returns prediction."""
    
    if 'audio' not in request.files:
        return jsonify({"error": "No audio file provided"}), 400
    
    audio_file = request.files['audio']
    if audio_file.filename == '':
        return jsonify({"error": "No selected file"}), 400

    # Use NamedTemporaryFile to save the uploaded file securely (REQUIRED for pydub read)
    temp_input_path = None
    cleaned_wav_path = None
    
    try:
        # Save the uploaded file to a temporary location
        with tempfile.NamedTemporaryFile(delete=False) as temp_input:
            temp_input_path = temp_input.name
            audio_file.save(temp_input_path)

        # 1. Run the core prediction logic
        prediction, confidence, cleaned_wav_path = process_and_predict(temp_input_path)
        
        # 2. Read the cleaned WAV file bytes
        with open(cleaned_wav_path, 'rb') as f:
            wav_bytes = f.read()

        # 3. Base64 encode the bytes to send back to Dart
        wav_base64 = base64.b64encode(wav_bytes).decode('utf-8')
        
        # 4. Return the result
        return jsonify({
            "prediction": prediction.lower(),
            "confidence": confidence,
            "wav_base64": wav_base64
        }), 200
    
    except Exception as e:
        print(f"Prediction failed: {e}")
        return jsonify({"error": str(e)}), 500
        
    finally:
        # Cleanup: Remove the required temporary files used for the input and final output
        if temp_input_path and os.path.exists(temp_input_path):
            os.remove(temp_input_path)
        if cleaned_wav_path and os.path.exists(cleaned_wav_path):
            os.remove(cleaned_wav_path)


if __name__ == '__main__':
    # When running locally, ensure the correct packages are installed
    app.run(debug=True, port=5000)