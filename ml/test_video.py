#!/usr/bin/env python3
"""
test_video.py — Test BISINDO model dengan video file lokal.

Pipeline identik dengan training (kaggle_bisindo_wl.py):
  video → uniform 30-frame subsample → MediaPipe → 94 floats
  → std-normalize → temporal derivatives (94→282) → TFLite → top-3 prediksi

Usage:
  python3 ml/test_video.py ml/video.mp4
  python3 ml/test_video.py ml/video.mp4 --label terima_kasih
  python3 ml/test_video.py ml/video.mp4 --all-windows

Prerequisite:
  pip install mediapipe>=0.10 opencv-python numpy tensorflow

NOTE: mediapipe 0.10+ pakai Tasks API — otomatis download model (~7MB) saat pertama kali.
"""

import sys
import argparse
import json
import urllib.request
from pathlib import Path

import cv2
import numpy as np

# ── Paths ─────────────────────────────────────────────────────────────────────
ROOT         = Path(__file__).parent.parent
TFLITE_PATH  = ROOT / "assets/models/bisindo_wl_model.tflite"
LABELS_PATH  = ROOT / "assets/models/bisindo_wl_labels.json"
ML_DIR       = ROOT / "ml"

# MediaPipe Tasks model files (auto-download)
HAND_TASK_URL = "https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task"
POSE_TASK_URL = "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/latest/pose_landmarker_lite.task"
HAND_TASK_PATH = ML_DIR / "hand_landmarker.task"
POSE_TASK_PATH = ML_DIR / "pose_landmarker_lite.task"

SEQUENCE_LEN = 30
FEATURE_DIM  = 100
POSE_ANCHOR_IDX = [0, 11, 12, 7, 8, 13, 14]  # nose, L_shoulder, R_shoulder, L_ear, R_ear, L_elbow, R_elbow


# ── Download helper ───────────────────────────────────────────────────────────
def _download_if_needed(url: str, path: Path):
    if path.exists():
        return
    print(f"  Downloading {path.name} ...")
    path.parent.mkdir(parents=True, exist_ok=True)
    urllib.request.urlretrieve(url, path)
    print(f"  ✅ {path.name} ({path.stat().st_size // 1024} KB)")


# ── MediaPipe Tasks API (0.10+) ───────────────────────────────────────────────
def _load_mediapipe_tasks():
    """Load HandLandmarker + PoseLandmarker via Tasks API (mediapipe 0.10+)."""
    from mediapipe.tasks import python as mp_python
    from mediapipe.tasks.python import vision
    from mediapipe.tasks.python.core.base_options import BaseOptions

    _download_if_needed(HAND_TASK_URL, HAND_TASK_PATH)
    _download_if_needed(POSE_TASK_URL, POSE_TASK_PATH)

    hand_opts = vision.HandLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=str(HAND_TASK_PATH)),
        running_mode=vision.RunningMode.IMAGE,
        num_hands=2,
        min_hand_detection_confidence=0.3,
        min_tracking_confidence=0.3,
    )
    pose_opts = vision.PoseLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=str(POSE_TASK_PATH)),
        running_mode=vision.RunningMode.IMAGE,
        min_pose_detection_confidence=0.3,
    )

    hand_det = vision.HandLandmarker.create_from_options(hand_opts)
    pose_det = vision.PoseLandmarker.create_from_options(pose_opts)
    return hand_det, pose_det, "tasks"


# ── MediaPipe solutions API (0.9.x / beberapa 0.10.x) ────────────────────────
def _load_mediapipe_solutions():
    """Legacy solutions API — works on mediapipe 0.9.x."""
    import mediapipe as mp
    try:
        _ = mp.solutions.hands
        return mp.solutions.hands, mp.solutions.pose, "solutions"
    except AttributeError:
        pass
    try:
        from mediapipe import solutions as _sol
        _ = _sol.hands
        return _sol.hands, _sol.pose, "solutions"
    except (ImportError, AttributeError):
        pass
    raise ImportError("solutions API tidak tersedia")


def load_mediapipe():
    try:
        return _load_mediapipe_solutions()
    except ImportError:
        return _load_mediapipe_tasks()


# ── Feature extraction ────────────────────────────────────────────────────────

def _extract_features_solutions(hand_result, pose_result) -> np.ndarray:
    """Solutions API version (mediapipe 0.9.x)."""
    out = np.full(FEATURE_DIM, np.nan, dtype=np.float32)
    nose_x, nose_y = 0.5, 0.5
    has_right = False
    has_left  = False

    if pose_result.pose_landmarks:
        lm = pose_result.pose_landmarks.landmark
        nose_x = lm[0].x
        nose_y = lm[0].y
        for i, idx in enumerate(POSE_ANCHOR_IDX):
            out[84 + i*2]     = lm[idx].x - nose_x
            out[84 + i*2 + 1] = lm[idx].y - nose_y

    if hand_result.multi_hand_landmarks is not None:
        for hand_lm in hand_result.multi_hand_landmarks:
            is_right = _anatomical_is_right(hand_lm.landmark)
            base = 0 if is_right else 42
            if is_right:
                has_right = True
            else:
                has_left = True
            for j, lm in enumerate(hand_lm.landmark):
                out[base + j*2]     = lm.x - nose_x
                out[base + j*2 + 1] = lm.y - nose_y

    out[98] = 1.0 if has_right else np.nan
    out[99] = 1.0 if has_left  else np.nan
    return out


def _anatomical_is_right(landmarks) -> bool:
    """
    Determine true handedness from palm geometry — API-agnostic.
    Sama dengan training pipeline (kaggle_bisindo_wl.py) dan Flutter.
    Tidak bergantung pada label "Right"/"Left" dari mediapipe (berbeda antar versi).
    """
    w   = landmarks[0]
    i5  = landmarks[5]
    p17 = landmarks[17]
    t4  = landmarks[4]
    p20 = landmarks[20]
    cross_z = (i5.x - w.x) * (p17.y - w.y) - (i5.y - w.y) * (p17.x - w.x)
    thumb_vs_pinky = t4.x - p20.x
    return (cross_z >= 0 and thumb_vs_pinky <= 0) or (cross_z < 0 and thumb_vs_pinky > 0)


def _extract_features_tasks(hand_result, pose_result) -> np.ndarray:
    """Tasks API version (mediapipe 0.10+) dengan anatomical handedness."""
    out = np.full(FEATURE_DIM, np.nan, dtype=np.float32)
    nose_x, nose_y = 0.5, 0.5
    has_right = False
    has_left  = False

    if pose_result.pose_landmarks:
        lm = pose_result.pose_landmarks[0]
        nose_x = lm[0].x
        nose_y = lm[0].y
        for i, idx in enumerate(POSE_ANCHOR_IDX):
            out[84 + i*2]     = lm[idx].x - nose_x
            out[84 + i*2 + 1] = lm[idx].y - nose_y

    if hand_result.hand_landmarks:
        for hand_lm in hand_result.hand_landmarks:
            is_right = _anatomical_is_right(hand_lm)
            base = 0 if is_right else 42
            if is_right:
                has_right = True
            else:
                has_left = True
            for j, lm in enumerate(hand_lm):
                out[base + j*2]     = lm.x - nose_x
                out[base + j*2 + 1] = lm.y - nose_y

    out[98] = 1.0 if has_right else np.nan
    out[99] = 1.0 if has_left  else np.nan
    return out


def extract_frame_features(rgb_frame: np.ndarray, hand_det, pose_det, api: str) -> np.ndarray:
    """RGB frame → 94-float feature vector."""
    import mediapipe as mp

    if api == "tasks":
        from mediapipe.tasks.python import vision as mp_vision
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb_frame)
        h_result = hand_det.detect(mp_image)
        p_result = pose_det.detect(mp_image)
        return _extract_features_tasks(h_result, p_result)
    else:
        h_result = hand_det.process(rgb_frame)
        p_result = pose_det.process(rgb_frame)
        return _extract_features_solutions(h_result, p_result)


# ── Normalization & derivatives ───────────────────────────────────────────────

def normalize_sequence_std(seq: np.ndarray) -> np.ndarray:
    mean = np.nanmean(seq)
    std  = np.nanstd(seq)
    if std < 1e-6:
        std = 1.0
    seq = (seq - mean) / std
    return np.nan_to_num(seq, nan=0.0, posinf=0.0, neginf=0.0).astype(np.float32)


def add_temporal_derivatives(seq: np.ndarray) -> np.ndarray:
    """(30, 94) → (30, 282): position + velocity + acceleration."""
    vel = np.zeros_like(seq)
    acc = np.zeros_like(seq)
    vel[1:]  = seq[1:]  - seq[:-1]
    acc[2:]  = seq[2:]  - seq[:-2]
    return np.concatenate([seq, vel, acc], axis=-1).astype(np.float32)


# ── Video processing ──────────────────────────────────────────────────────────

def extract_video_uniform(video_path: str, hand_det, pose_det, api: str) -> np.ndarray:
    """Uniform 30-frame subsample — IDENTIK pipeline training."""
    cap   = cv2.VideoCapture(str(video_path))
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    fps   = cap.get(cv2.CAP_PROP_FPS)
    dur   = total / fps if fps > 0 else 0

    print(f"  Video: {Path(video_path).name}")
    print(f"  Total frames: {total}, FPS: {fps:.1f}, Durasi: {dur:.1f}s")

    if total <= 0:
        cap.release()
        return np.zeros((SEQUENCE_LEN, FEATURE_DIM), dtype=np.float32)

    indices = np.linspace(0, total - 1, SEQUENCE_LEN, dtype=int)
    seq = []
    hand_frames = 0

    for fi in indices:
        cap.set(cv2.CAP_PROP_POS_FRAMES, int(fi))
        ret, frame = cap.read()
        if not ret:
            seq.append(np.full(FEATURE_DIM, np.nan, dtype=np.float32))
            continue
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        feat = extract_frame_features(rgb, hand_det, pose_det, api)
        # Check if hand detected
        if not np.all(np.isnan(feat[:84])):
            hand_frames += 1
        seq.append(feat)

    cap.release()

    while len(seq) < SEQUENCE_LEN:
        seq.append(np.full(FEATURE_DIM, np.nan, dtype=np.float32))

    raw = np.array(seq[:SEQUENCE_LEN], dtype=np.float32)
    print(f"  Tangan terdeteksi: {hand_frames}/{SEQUENCE_LEN} frame")
    return normalize_sequence_std(raw)


FLUTTER_FRAME_SKIP = 2  # Flutter addFrame() hanya terima setiap 2nd frame → 15fps efektif

def extract_video_sliding(video_path: str, hand_det, pose_det, api: str):
    """Semua frame → list of sliding windows — IDENTIK Flutter streaming.

    Flutter gesture_service.dart pakai frame decimation (_frameSkipRate=2):
    kamera ~30fps → hanya setiap 2nd frame masuk buffer → 30 frame = ~2 detik.
    Kita replicate hal yang sama di sini.
    """
    cap   = cv2.VideoCapture(str(video_path))
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    fps   = cap.get(cv2.CAP_PROP_FPS)
    print(f"  Video: {Path(video_path).name}")
    print(f"  Total frames: {total}, FPS: {fps:.1f}")
    print(f"  Frame decimation: keep every {FLUTTER_FRAME_SKIP}nd frame → {fps/FLUTTER_FRAME_SKIP:.1f}fps efektif")

    # Read semua frame, apply decimation seperti Flutter
    decimated_frames = []
    frame_counter = 0
    for _ in range(total):
        ret, frame = cap.read()
        frame_counter += 1
        if not ret:
            frame_counter += 1
            continue
        if frame_counter % FLUTTER_FRAME_SKIP != 0:
            continue  # skip — matches Flutter _frameSkipRate
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        decimated_frames.append(extract_frame_features(rgb, hand_det, pose_det, api))
    cap.release()

    n_decimated = len(decimated_frames)
    print(f"  Setelah decimation: {n_decimated} frames (covers {n_decimated/fps*FLUTTER_FRAME_SKIP:.1f}s)")

    # Sliding window over decimated frames
    windows = []
    step = max(1, SEQUENCE_LEN // 6)
    for start in range(0, max(1, n_decimated - SEQUENCE_LEN + 1), step):
        window = decimated_frames[start:start + SEQUENCE_LEN]
        while len(window) < SEQUENCE_LEN:
            window.insert(0, np.full(FEATURE_DIM, np.nan, dtype=np.float32))
        raw = np.array(window[:SEQUENCE_LEN], dtype=np.float32)
        windows.append((start, normalize_sequence_std(raw)))
    return windows


# ── TFLite inference ──────────────────────────────────────────────────────────

def run_inference(seq_normalized: np.ndarray, interpreter, labels: dict) -> list:
    seq_with_deriv = add_temporal_derivatives(seq_normalized)
    input_data = seq_with_deriv[np.newaxis].astype(np.float32)

    inp  = interpreter.get_input_details()
    out  = interpreter.get_output_details()
    interpreter.set_tensor(inp[0]['index'], input_data)
    interpreter.invoke()
    probs = interpreter.get_tensor(out[0]['index'])[0]

    top3_idx = np.argsort(probs)[::-1][:3]
    return [(labels[str(i)], float(probs[i])) for i in top3_idx]


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("video", help="Path ke video (.mp4)")
    parser.add_argument("--label", default=None, help="Label yang diharapkan")
    parser.add_argument("--all-windows", action="store_true",
                        help="Test sliding window (seperti Flutter)")
    parser.add_argument("--model",  default=str(TFLITE_PATH))
    parser.add_argument("--labels", default=str(LABELS_PATH))
    args = parser.parse_args()

    tflite_path = Path(args.model)
    labels_path = Path(args.labels)

    if not tflite_path.exists():
        print(f"❌ Model tidak ditemukan: {tflite_path}"); sys.exit(1)
    if not labels_path.exists():
        print(f"❌ Labels tidak ditemukan: {labels_path}"); sys.exit(1)
    if not Path(args.video).exists():
        print(f"❌ Video tidak ditemukan: {args.video}"); sys.exit(1)

    # Load TFLite
    try:
        import tflite_runtime.interpreter as tflite
        interpreter = tflite.Interpreter(model_path=str(tflite_path))
    except ImportError:
        import tensorflow as tf
        interpreter = tf.lite.Interpreter(model_path=str(tflite_path))
    interpreter.allocate_tensors()

    with open(labels_path) as f:
        raw_labels = json.load(f)
    if "index_to_label" in raw_labels:
        labels = {str(k): v for k, v in raw_labels["index_to_label"].items()}
    else:
        labels = {str(k): v for k, v in raw_labels.items()}

    print(f"\n{'='*55}")
    print(f"  BISINDO Model Test")
    print(f"  Model : {tflite_path.name}")
    print(f"  Labels: {len(labels)} kelas")
    print(f"{'='*55}\n")

    # Load MediaPipe
    result = load_mediapipe()
    hand_mod, pose_mod, api = result
    print(f"  MediaPipe API: {api}\n")

    if api == "tasks":
        # Tasks API: detectors already created
        hand_det, pose_det = hand_mod, pose_mod
        if args.all_windows:
            _run_sliding(args, hand_det, pose_det, api, interpreter, labels)
        else:
            _run_uniform(args, hand_det, pose_det, api, interpreter, labels)
    else:
        # Solutions API: need context managers
        with (hand_mod.Hands(
                    static_image_mode=False,
                    max_num_hands=2,
                    min_detection_confidence=0.3,
                    model_complexity=1,
              ) as hand_det,
              pose_mod.Pose(
                    static_image_mode=False,
                    min_detection_confidence=0.3,
                    model_complexity=1,
              ) as pose_det):
            if args.all_windows:
                _run_sliding(args, hand_det, pose_det, api, interpreter, labels)
            else:
                _run_uniform(args, hand_det, pose_det, api, interpreter, labels)


def _run_uniform(args, hand_det, pose_det, api, interpreter, labels):
    print(f"[UNIFORM 30-FRAME SUBSAMPLE] — identik training pipeline\n")
    seq = extract_video_uniform(args.video, hand_det, pose_det, api)
    top3 = run_inference(seq, interpreter, labels)

    print(f"\n  Hasil prediksi:")
    for i, (label, conf) in enumerate(top3):
        marker = " ✅" if label == args.label else ""
        print(f"    {'#1 #2 #3'.split()[i]}  {label:<20} {conf*100:5.1f}%{marker}")

    if args.label:
        correct = top3[0][0] == args.label
        print(f"\n  Expected: {args.label}")
        print(f"  Result  : {'✅ BENAR' if correct else '❌ SALAH'} → prediksi: {top3[0][0]}")


def _run_sliding(args, hand_det, pose_det, api, interpreter, labels):
    print(f"[SLIDING WINDOW + DECIMATION skip={FLUTTER_FRAME_SKIP}] — IDENTIK Flutter streaming\n")
    windows = extract_video_sliding(args.video, hand_det, pose_det, api)
    print(f"\n  Total windows: {len(windows)}\n")

    vote_counts = {}
    for start, seq in windows:
        top3 = run_inference(seq, interpreter, labels)
        for label, conf in top3:
            vote_counts[label] = vote_counts.get(label, 0) + conf
        t3_str = "  ".join(f"{l}({c*100:.0f}%)" for l, c in top3)
        marker = " ✅" if args.label and top3[0][0] == args.label else ""
        print(f"  f{start:5d}  {t3_str}{marker}")

    print(f"\n  Voting (sum confidence):")
    for label, score in sorted(vote_counts.items(), key=lambda x: -x[1])[:5]:
        marker = " ✅" if label == args.label else ""
        print(f"    {label:<20} {score:.2f}{marker}")


if __name__ == "__main__":
    main()
