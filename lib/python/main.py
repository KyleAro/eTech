# this is the python file that turns our ml to an api.

from flask import Flask, request, jsonify
import librosa, numpy as np, joblib, os, uuid, traceback
from werkzeug.utils import secure_filename
from pydub import AudioSegment  # <-- added for universal audio handling

app = Flask(__name__)

# --- Load your saved model and scaler once ---
MODEL_PATH = r"C:\Users\User\OneDrive - Innobyte\Desktop\etech\lib\python\duckling_svm_rbf_day4-13.pkl"
SCALER_PATH = r"C:\Users\User\OneDrive - Innobyte\Desktop\etech\lib\python\duckling_scaler_day4-13.pkl"

model = joblib.load(MODEL_PATH)
scaler = joblib.load(SCALER_PATH)

print("Model and scaler loaded successfully!")

# --- Feature extraction function ---
def extract_features(file_path):
    y, sr = librosa.load(file_path, sr=None)
    if y.size == 0:
        raise ValueError("Audio file is empty")

    y = librosa.util.normalize(y)

    mfccs = np.mean(librosa.feature.mfcc(y=y, sr=sr, n_mfcc=13).T, axis=0)
    spectral_centroid = np.mean(librosa.feature.spectral_centroid(y=y, sr=sr))
    spectral_rolloff = np.mean(librosa.feature.spectral_rolloff(y=y, sr=sr))
    zero_crossing_rate = np.mean(librosa.feature.zero_crossing_rate(y))
    pitches, magnitudes = librosa.piptrack(y=y, sr=sr)
    pitch = np.mean(pitches[pitches > 0]) if np.any(pitches > 0) else 0

    features = np.hstack([mfccs, spectral_centroid, spectral_rolloff, zero_crossing_rate, pitch])
    features = np.nan_to_num(features)  # Replace NaNs with 0
    return features.reshape(1, -1)

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

    # Convert to WAV if not already
    converted_path = os.path.join('temp', f"{uuid.uuid4().hex}.wav")
    try:
        audio = AudioSegment.from_file(orig_path)
        audio = audio.set_channels(1).set_frame_rate(16000)
        audio.export(converted_path, format="wav")
    except Exception as e:
        print("Audio conversion failed:", e)
        return jsonify({'error': f'Audio conversion failed: {e}'}), 500

    try:
        features = extract_features(converted_path)
        print("Extracted features shape:", features.shape)

        if features.shape[1] != scaler.mean_.shape[0]:
            raise ValueError(f"Feature length {features.shape[1]} does not match scaler expected {scaler.mean_.shape[0]}")

        features_scaled = scaler.transform(features)
        probs = model.predict_proba(features_scaled)[0]
        print("Model classes:", model.classes_)
        print("Scaler mean shape:", scaler.mean_.shape)

        pred_class = model.classes_[np.argmax(probs)]
        confidence = float(np.max(probs))
        gender = "Male" if "male" in pred_class.lower() else "Female"

        return jsonify({
            'prediction': gender.capitalize(),
            'confidence': round(float(confidence or 0) * 100, 2)
        })

    except Exception as e:
        print("Prediction error:", e)
        print(traceback.format_exc())
        return jsonify({'error': str(e), 'trace': traceback.format_exc()}), 500

    finally:
        if os.path.exists(orig_path):
            os.remove(orig_path)
        if os.path.exists(converted_path):
            os.remove(converted_path)

if __name__ == '__main__':
    app.run(host="0.0.0.0", port=5000, debug=True)
