import os
import numpy as np
import pandas as pd
import librosa
from sklearn.svm import SVC
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score, classification_report
from sklearn.preprocessing import StandardScaler
import joblib

# === NEW: shared cleaning module ===
# clean_audio() does HPF + LPF + spectral gate + normalize + trim.
# It replaces librosa.load() so training and inference see identical data.
# CRITICAL: any future change to audio_clean.py requires retraining the model.
from audio_clean import clean_audio

# === SETTINGS ===
dataset_path = r"C:\Users\User\OneDrive - Innobyte\Desktop\etech\lib\python\Day8"

# === FUNCTION: Extract audio features ===
def extract_features(file_path):
    try:
        # CHANGED: was `y, sr = librosa.load(file_path, sr=None)` followed by
        # `y = librosa.util.normalize(y)`. Both of those are now inside
        # clean_audio() — and clean_audio also does HPF/LPF/spectral gate/trim.
        y, sr = clean_audio(file_path)

        if y.size == 0:
            return None

        # Core Features — UNCHANGED so the feature vector layout stays identical
        # to the old model's scaler (13 MFCCs + 4 scalars = 17 dims).
        mfccs = np.mean(librosa.feature.mfcc(y=y, sr=sr, n_mfcc=13).T, axis=0)
        spectral_centroid = np.mean(librosa.feature.spectral_centroid(y=y, sr=sr))
        spectral_rolloff = np.mean(librosa.feature.spectral_rolloff(y=y, sr=sr))
        zero_crossing_rate = np.mean(librosa.feature.zero_crossing_rate(y))
        pitches, magnitudes = librosa.piptrack(y=y, sr=sr)
        pitch = np.mean(pitches[pitches > 0]) if np.any(pitches > 0) else 0

        features = np.hstack([mfccs, spectral_centroid, spectral_rolloff, zero_crossing_rate, pitch])
        return features

    except Exception as e:
        print(f"⚠️ Error processing {file_path}: {e}")
        return None

# === STEP 1: Load files and extract features ===
labels_folders = [f for f in os.listdir(dataset_path) if os.path.isdir(os.path.join(dataset_path, f))]
data = []
labels = []

for label in labels_folders:
    folder_path = os.path.join(dataset_path, label)
    print(f"\nExtracting features for label: {label}")
    for file in os.listdir(folder_path):
        if file.lower().endswith((".wav", ".mp3")):  # Accept both wav and mp3
            path = os.path.join(folder_path, file)
            features = extract_features(path)
            if features is not None:
                data.append(features)
                labels.append(label)
            else:
                print(f"Skipping file: {file}")

if len(data) == 0:
    raise ValueError(" No valid audio files found in dataset.")

# === STEP 2: Convert to DataFrame and normalize ===
cols = [f"mfcc{i+1}" for i in range(13)] + ["spectral_centroid", "spectral_rolloff", "zero_crossing_rate", "pitch"]
df = pd.DataFrame(data, columns=cols)
df["label"] = labels

df.to_csv(os.path.join(dataset_path, "duckling_features_enhanced.csv"), index=False)
print(" Feature extraction complete.")

X = df.drop("label", axis=1)
y = df["label"]
scaler = StandardScaler()
X_scaled = scaler.fit_transform(X)

X_train, X_test, y_train, y_test = train_test_split(X_scaled, y, test_size=0.2, random_state=42)

# === STEP 3: Train SVM with RBF kernel ===
model = SVC(kernel="rbf", gamma="scale", probability=True)
model.fit(X_train, y_train)

y_pred = model.predict(X_test)
print("\n📊 Classification Report:")
print(classification_report(y_test, y_pred))
print(f" Accuracy: {round(accuracy_score(y_test, y_pred)*100,2)}%")

# === STEP 4: Save model & scaler ===
# NOTE: model filename bumped to mark that this generation was trained on
# cleaned audio. Old .pkl files will NOT work with the new inference path —
# they expect un-cleaned features.
joblib.dump(model, os.path.join(dataset_path, "duckling_svm_rbf_cleaned.pkl"))
joblib.dump(scaler, os.path.join(dataset_path, "duckling_scaler_cleaned.pkl"))
print("💾 Model and scaler saved successfully.")