# try.py (updated)
# --- install these first ---
# pip install flask librosa numpy joblib pydub soundfile

from flask import Flask, request, jsonify
import librosa, numpy as np, joblib, os, uuid, traceback, io
from werkzeug.utils import secure_filename
from pydub import AudioSegment, silence
import concurrent.futures
import warnings

warnings.filterwarnings("ignore")

app = Flask(__name__)

# --- Load your saved model and scaler once ---
MODEL_PATH = r"duckling_svm_rbf_day4-13.pkl"
SCALER_PATH = r"duckling_scaler_day4-13.pkl"

model = joblib.load(MODEL_PATH)
scaler = joblib.load(SCALER_PATH)

print("Model and scaler loaded successfully!")

# --- Feature extraction function (works from numpy y,sr or file path) ---
def extract_features_from_y(y, sr):
    if y is None or y.size == 0:
        raise ValueError("Audio data is empty")

    y = librosa.util.normalize(y)

    mfccs = np.mean(librosa.feature.mfcc(y=y, sr=sr, n_mfcc=13).T, axis=0)
    spectral_centroid = np.mean(librosa.feature.spectral_centroid(y=y, sr=sr))
    spectral_rolloff = np.mean(librosa.feature.spectral_rolloff(y=y, sr=sr))
    zero_crossing_rate = np.mean(librosa.feature.zero_crossing_rate(y))
    pitches, magnitudes = librosa.piptrack(y=y, sr=sr)
    pitch = np.mean(pitches[pitches > 0]) if np.any(pitches > 0) else 0

    features = np.hstack([mfccs, spectral_centroid, spectral_rolloff, zero_crossing_rate, pitch])
    features = np.nan_to_num(features)
    return features.reshape(1, -1)

def extract_features(file_source):
    
    if hasattr(file_source, "read"):
        # file-like
        file_source.seek(0)
        y, sr = librosa.load(file_source, sr=None)
    else:
        y, sr = librosa.load(file_source, sr=None)
    return extract_features_from_y(y, sr)

# --- Helper: clean and split audio in-memory ---
def clean_and_split_audio_segment(audio_segment, clip_length_ms=3000, min_silence_len=400, silence_thresh=-40):
    # Split on silence into chunks
    chunks = silence.split_on_silence(
        audio_segment,
        min_silence_len=min_silence_len,
        silence_thresh=silence_thresh
    )

    if not chunks:
        chunks = [audio_segment]

    # Recombine with short silent padding
    combined = AudioSegment.empty()
    for c in chunks:
        combined += c + AudioSegment.silent(duration=100)

    # Export cleaned full audio
    cleaned_path = os.path.join('temp', f"{uuid.uuid4().hex}_cleaned.wav")
    combined.export(cleaned_path, format="wav")

    # Slice into fixed-length clips
    clips = []
    for start in range(0, len(combined), clip_length_ms):
        clip = combined[start:start + clip_length_ms]
        if len(clip) > 1000:
            clips.append(clip)

    # RETURN BOTH
    return clips, cleaned_path
# --- Worker: process a single AudioSegment clip and return probability vector ---
def process_clip_predict_probs(clip):
    
    try:
        wav_io = io.BytesIO()
        clip.export(wav_io, format="wav")
        wav_io.seek(0)

        # Load with librosa from BytesIO
        y, sr = librosa.load(wav_io, sr=None)
        features = extract_features_from_y(y, sr)

        if features.shape[1] != scaler.mean_.shape[0]:
            # Feature length mismatch, return None to skip
            return None

        features_scaled = scaler.transform(features)
        probs = model.predict_proba(features_scaled)[0]
        return probs
    except Exception as e:
        # Log and return None so it can be skipped
        print("Clip processing error:", e)
        return None

# --- Prediction endpoint ---
@app.route('/predict', methods=['POST'])
def predict():
    if 'file' not in request.files:
        return jsonify({'error': 'No file uploaded'}), 400

    file = request.files['file']
    if file.filename == '':
        return jsonify({'error': 'Empty filename'}), 400

    os.makedirs('temp', exist_ok=True)
    orig_filename = secure_filename(file.filename)
    orig_path = os.path.join('temp', orig_filename)
    file.save(orig_path)

    converted_path = os.path.join('temp', f"{uuid.uuid4().hex}.wav")
    cleaned_path = None  # will store path of cleaned audio

    try:
        # --- Convert to mono 16kHz WAV ---
        audio = AudioSegment.from_file(orig_path)
        audio = audio.set_channels(1).set_frame_rate(16000)
        audio.export(converted_path, format="wav")

        # --- Load and clean/split ---
        audio_segment = AudioSegment.from_file(converted_path)
        clips, cleaned_path = clean_and_split_audio_segment(
            audio_segment,
            clip_length_ms=3000,
            min_silence_len=400,
            silence_thresh=-40
        )

        if not clips:
            raise ValueError("No valid clips after cleaning/splitting")

        # --- Process clips in parallel ---
        max_workers = min(8, (os.cpu_count() or 2))
        all_probs = []
        with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures = [executor.submit(process_clip_predict_probs, clip) for clip in clips]
            for fut in concurrent.futures.as_completed(futures):
                probs = fut.result()
                if probs is not None:
                    all_probs.append(probs)

        if not all_probs:
            raise ValueError("No valid predictions from any clip")

        # --- Average probabilities and decide prediction ---
        avg_probs = np.mean(all_probs, axis=0)
        max_idx = int(np.argmax(avg_probs))
        pred_class = model.classes_[max_idx]
        gender = "Male" if "male" in pred_class.lower() else "Female"
        confidence_val = float(avg_probs[max_idx])

        # Optional: per-class confidence
        confidence_male = float(avg_probs[model.classes_.tolist().index('male')]) * 100 \
            if 'male' in model.classes_ else 0.0
        confidence_female = float(avg_probs[model.classes_.tolist().index('female')]) * 100 \
            if 'female' in model.classes_ else 0.0

        return jsonify({
            'prediction': gender.capitalize(),
            'confidence': round(confidence_val * 100, 2),
            'confidence_male': round(confidence_male, 2),
            'confidence_female': round(confidence_female, 2)
        })

    except Exception as e:
        print("Prediction error:", e)
        print(traceback.format_exc())
        return jsonify({'error': str(e), 'trace': traceback.format_exc()}), 500

    finally:
        # --- Cleanup all temp files safely ---
        for path in [orig_path, converted_path, cleaned_path]:
            if path and os.path.exists(path):
                os.remove(path)
if __name__ == '__main__':
    app.run(host="0.0.0.0", port=5000, debug=True)
