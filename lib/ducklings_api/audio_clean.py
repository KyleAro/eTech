"""
audio_clean.py
==============

Single source of truth for audio cleaning across this project.
USED BY BOTH TRAINING AND INFERENCE. Do not branch the logic.

Pipeline:
    1. Load + resample to TARGET_SR (16 kHz).
    2. High-pass at 300 Hz   — kills wind rumble, AC hum, handling thumps.
    3. Low-pass at 8 kHz     — kills hiss above duckling vocal range.
    4. Spectral gating       — adaptive per-recording noise subtraction.
    5. Peak-normalize        — consistent loudness across recordings.
    6. Silence trim          — drops dead air at the duckling-appropriate threshold.

The function `clean_audio(path) -> (y, sr)` returns a clean mono float32
NumPy array and the sample rate. This is a drop-in replacement for
`librosa.load(...)` everywhere the project loads audio.

Why these choices for ducklings (not human speech):
- 300 Hz HPF is below most duckling fundamentals (peep range ~1.5–5 kHz).
- 8 kHz LPF keeps the harmonics that carry MFCC discrimination but kills hiss.
- We do NOT use DeepFilterNet / RNNoise / Resemble Enhance — those were
  trained on speech and will likely treat duckling vocalizations as noise.
- `noisereduce` is signal-agnostic: it learns the noise floor from the
  recording itself, no labeled "noise" sample needed.

Install deps (add to requirements.txt):
    librosa>=0.10
    soundfile>=0.12
    scipy>=1.10
    noisereduce>=3.0
    numpy
"""

from __future__ import annotations

import io
from typing import Tuple

import numpy as np
import librosa
import soundfile as sf
import noisereduce as nr
from scipy.signal import butter, sosfiltfilt


# =============================================================================
# CONFIG — keep these constants identical at training and inference time.
# =============================================================================

TARGET_SR = 16_000          # 16 kHz: covers duckling range, ~3x smaller files
HPF_HZ = 300.0              # high-pass cutoff
LPF_HZ = 8_000.0            # low-pass cutoff (must be < TARGET_SR/2)
PEAK_DBFS = -3.0            # post-normalize peak level
SILENCE_TOP_DB = 30         # librosa.effects.trim threshold (dB below max)
NR_PROP_DECREASE = 0.8      # how aggressively to subtract estimated noise
NR_STATIONARY = False       # adaptive (non-stationary) noise estimate

# Safety: if LPF >= Nyquist, scale it down.
if LPF_HZ >= TARGET_SR / 2:
    LPF_HZ = (TARGET_SR / 2) - 100


# =============================================================================
# INTERNAL HELPERS
# =============================================================================

def _bandpass_sos(sr: int):
    """Build a 4th-order Butterworth band-pass as second-order sections.

    SOS form is numerically stable for tight bands; sosfiltfilt gives
    zero-phase filtering so we don't smear the duckling transients.
    """
    nyq = sr / 2
    low = HPF_HZ / nyq
    high = LPF_HZ / nyq
    return butter(N=4, Wn=[low, high], btype="bandpass", output="sos")


def _peak_normalize(y: np.ndarray, target_dbfs: float = PEAK_DBFS) -> np.ndarray:
    """Scale signal so its peak sits at `target_dbfs`. Silent → unchanged."""
    peak = float(np.max(np.abs(y))) if y.size else 0.0
    if peak < 1e-9:
        return y
    target_linear = 10 ** (target_dbfs / 20)
    return (y / peak) * target_linear


# =============================================================================
# PUBLIC API
# =============================================================================

def clean_audio(
    path_or_bytes,
    sr_out: int = TARGET_SR,
    apply_spectral_gate: bool = True,
) -> Tuple[np.ndarray, int]:
    """Load and clean an audio file. Returns (y, sr).

    Parameters
    ----------
    path_or_bytes : str | bytes | file-like
        Path on disk, or raw bytes, or any object soundfile/librosa can read.
    sr_out : int
        Target sample rate. Keep default unless you know why.
    apply_spectral_gate : bool
        Toggle spectral gating. Useful for ablation studies; default True.

    Returns
    -------
    y : np.ndarray, float32, mono
    sr : int (== sr_out)
    """
    # 1. Load + resample + force mono.
    #    librosa handles many formats via audioread; for raw bytes we hand to
    #    soundfile first to avoid temp files.
    if isinstance(path_or_bytes, (bytes, bytearray)):
        y, sr = sf.read(io.BytesIO(path_or_bytes), dtype="float32", always_2d=False)
        if y.ndim > 1:
            y = np.mean(y, axis=1)
        if sr != sr_out:
            y = librosa.resample(y, orig_sr=sr, target_sr=sr_out)
            sr = sr_out
    else:
        y, sr = librosa.load(path_or_bytes, sr=sr_out, mono=True)

    if y.size == 0:
        return y.astype(np.float32), sr_out

    # 2 + 3. Band-pass (HPF + LPF combined).
    sos = _bandpass_sos(sr)
    y = sosfiltfilt(sos, y).astype(np.float32)

    # 4. Spectral gating — adaptive noise estimate from the recording itself.
    if apply_spectral_gate:
        try:
            y = nr.reduce_noise(
                y=y,
                sr=sr,
                stationary=NR_STATIONARY,
                prop_decrease=NR_PROP_DECREASE,
            ).astype(np.float32)
        except Exception as e:
            # Don't fail the whole pipeline if noisereduce hiccups on a short clip.
            print(f"⚠️ Spectral gating skipped: {e}")

    # 5. Peak-normalize before trimming, so trim threshold is meaningful.
    y = _peak_normalize(y)

    # 6. Trim leading/trailing silence (per-recording, conservative threshold).
    y, _ = librosa.effects.trim(y, top_db=SILENCE_TOP_DB)

    return y.astype(np.float32), sr


def clean_audio_to_wav_bytes(path_or_bytes) -> Tuple[bytes, int]:
    """Convenience: clean → return WAV-encoded bytes + sample rate.

    Used by the Flask endpoint to return cleaned audio to the Flutter app.
    """
    y, sr = clean_audio(path_or_bytes)
    buf = io.BytesIO()
    sf.write(buf, y, sr, format="WAV", subtype="PCM_16")
    return buf.getvalue(), sr


# =============================================================================
# CLI: quick sanity check.
#   python audio_clean.py input.wav cleaned.wav
# =============================================================================

if __name__ == "__main__":
    import sys

    if len(sys.argv) != 3:
        print("Usage: python audio_clean.py <input> <output.wav>")
        sys.exit(1)

    in_path, out_path = sys.argv[1], sys.argv[2]
    y, sr = clean_audio(in_path)
    sf.write(out_path, y, sr, subtype="PCM_16")
    print(f"✅ Cleaned: {in_path} → {out_path}  ({len(y)/sr:.2f}s @ {sr}Hz)")