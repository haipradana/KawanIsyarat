#!/usr/bin/env python3
"""
test_bisindo_alphabet.py — Webcam tester untuk model BISINDO alphabet.

Pakai MediaPipe Tasks API (mediapipe 0.10+) — kompatibel dengan installation
baru yang tidak punya `mp.solutions`. Auto-download hand_landmarker.task
kalau belum ada di ml/.

Fitur:
  - Skeleton 2 tangan (label Left/Right + warna) digambar manual
  - Prediksi top-3 dari model TFLite + slot info + dx/dy yang di-feed
  - Toggle mode hand-ordering: 'handedness' (SAMA training) vs 'xsort'
    (replika Flutter) → bandingkan mana yang benar

Usage:
  python ml/test_bisindo_alphabet.py                     # webcam
  python ml/test_bisindo_alphabet.py --camera 1
  python ml/test_bisindo_alphabet.py --image foto.jpg    # single image

Keys:
  q / ESC  quit
  m        toggle hand ordering (handedness ↔ xsort)
  f        toggle mirror (selfie view)
  s        snapshot PNG
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.request
from pathlib import Path

import cv2
import numpy as np

# ───── TFLite loader (flexible) ──────────────────────────────────────────────
try:
    import tensorflow as tf
    _make_interpreter = tf.lite.Interpreter
except ImportError:
    try:
        import tflite_runtime.interpreter as tflite_runtime  # type: ignore
        _make_interpreter = tflite_runtime.Interpreter
    except ImportError:
        print("[FATAL] Butuh tensorflow atau tflite_runtime.")
        sys.exit(1)

# ───── MediaPipe Tasks API ───────────────────────────────────────────────────
try:
    from mediapipe.tasks.python import vision
    from mediapipe.tasks.python.core.base_options import BaseOptions
    import mediapipe as mp
except ImportError as e:
    print(f"[FATAL] mediapipe tasks api tidak tersedia: {e}")
    sys.exit(1)


# ───── Paths ─────────────────────────────────────────────────────────────────
ROOT = Path(__file__).resolve().parent.parent
ML_DIR = ROOT / "ml"
DEFAULT_MODEL = ROOT / "assets/models/bisindo_alphabet_model_f32.tflite"
DEFAULT_LABELS = ROOT / "assets/models/bisindo_alphabet_labels.json"
HAND_TASK_URL = "https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task"
HAND_TASK_PATH = ML_DIR / "hand_landmarker.task"

# ───── Konstanta (sinkron dengan prepare_bisindo_alphabet.py) ────────────────
NUM_LANDMARKS = 21
NUM_FEATURES = NUM_LANDMARKS * 2 * 2 + 2  # 86

# 21 landmark connections (official MediaPipe Hands)
HAND_CONNECTIONS = [
    (0, 1), (1, 2), (2, 3), (3, 4),            # thumb
    (0, 5), (5, 6), (6, 7), (7, 8),            # index
    (5, 9), (9, 10), (10, 11), (11, 12),       # middle
    (9, 13), (13, 14), (14, 15), (15, 16),     # ring
    (13, 17), (17, 18), (18, 19), (19, 20),    # pinky
    (0, 17),                                    # palm base
]


# ───── Preprocessing (COPY PASTE dari prepare_bisindo_alphabet.py) ───────────
def normalize_hand(coords: np.ndarray) -> np.ndarray:
    min_xy = coords.min(axis=0)
    max_xy = coords.max(axis=0)
    span = np.maximum(max_xy - min_xy, 1e-6)
    return ((coords - min_xy) / span).flatten().astype(np.float32)


def make_features(hand_left: np.ndarray, hand_right: np.ndarray) -> np.ndarray:
    left_norm = normalize_hand(hand_left)
    right_norm = normalize_hand(hand_right)
    offset = hand_right.mean(axis=0) - hand_left.mean(axis=0)
    return np.concatenate([left_norm, right_norm, offset.astype(np.float32)])


def make_features_single_hand(hand: np.ndarray) -> np.ndarray:
    hand_norm = normalize_hand(hand)
    return np.concatenate([
        hand_norm,
        np.zeros(42, dtype=np.float32),
        np.zeros(2, dtype=np.float32),
    ])


# ───── TFLite wrapper ────────────────────────────────────────────────────────
class AlphabetClassifier:
    def __init__(self, model_path: Path, labels_path: Path):
        self.interp = _make_interpreter(model_path=str(model_path))
        self.interp.allocate_tensors()
        self.input_idx = self.interp.get_input_details()[0]['index']
        self.output_idx = self.interp.get_output_details()[0]['index']
        with open(labels_path) as f:
            self.labels = json.load(f)
        print(f"[OK] Model: {model_path.name}")
        print(f"[OK] Labels ({len(self.labels)}): {self.labels}")

    def predict(self, feat86: np.ndarray) -> np.ndarray:
        x = feat86.reshape(1, NUM_FEATURES).astype(np.float32)
        self.interp.set_tensor(self.input_idx, x)
        self.interp.invoke()
        return self.interp.get_tensor(self.output_idx)[0]

    def topk(self, scores: np.ndarray, k: int = 3):
        idxs = np.argsort(scores)[::-1][:k]
        return [(self.labels[i], float(scores[i])) for i in idxs]


# ───── MediaPipe helper ──────────────────────────────────────────────────────
def _download_if_needed(url: str, path: Path):
    if path.exists():
        return
    print(f"  Downloading {path.name} ...")
    path.parent.mkdir(parents=True, exist_ok=True)
    urllib.request.urlretrieve(url, path)
    print(f"  ✅ {path.name} ({path.stat().st_size // 1024} KB)")


def make_hand_detector():
    _download_if_needed(HAND_TASK_URL, HAND_TASK_PATH)
    opts = vision.HandLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=str(HAND_TASK_PATH)),
        running_mode=vision.RunningMode.IMAGE,
        num_hands=2,
        min_hand_detection_confidence=0.3,
        min_tracking_confidence=0.3,
    )
    return vision.HandLandmarker.create_from_options(opts)


def detect_hands(detector, frame_bgr):
    """Returns list of dicts: [{label, coords(21,2), landmarks(list of NormalizedLandmark)}]."""
    rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
    mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
    result = detector.detect(mp_image)

    parsed = []
    hand_lms = result.hand_landmarks or []
    handedness = result.handedness or []
    for i, lms in enumerate(hand_lms):
        coords = np.array([[p.x, p.y] for p in lms], dtype=np.float32)
        label = "?"
        if i < len(handedness) and handedness[i]:
            label = handedness[i][0].category_name  # "Left" / "Right"
        parsed.append({"label": label, "coords": coords, "landmarks": lms})
    return parsed


# ───── Drawing helpers ──────────────────────────────────────────────────────
COLOR_LEFT = (80, 220, 100)
COLOR_RIGHT = (80, 200, 255)
COLOR_UNK = (180, 180, 180)


def draw_hand(image, landmarks, color):
    h, w = image.shape[:2]
    pts = [(int(lm.x * w), int(lm.y * h)) for lm in landmarks]
    for a, b in HAND_CONNECTIONS:
        cv2.line(image, pts[a], pts[b], color, 2)
    for p in pts:
        cv2.circle(image, p, 3, color, -1)


def put_label(img, text, org, color=(255, 255, 255), bg=(0, 0, 0), scale=0.6, thickness=2):
    (tw, th), _ = cv2.getTextSize(text, cv2.FONT_HERSHEY_SIMPLEX, scale, thickness)
    x, y = org
    cv2.rectangle(img, (x - 4, y - th - 6), (x + tw + 4, y + 4), bg, -1)
    cv2.putText(img, text, (x, y), cv2.FONT_HERSHEY_SIMPLEX, scale, color, thickness)


# ───── Core: process single frame ────────────────────────────────────────────
def process_frame(frame_bgr, detector, classifier, mode: str):
    out = frame_bgr.copy()
    parsed = detect_hands(detector, frame_bgr)

    if not parsed:
        return out, [], "—", "no hands"

    # Draw every detected hand with its MediaPipe label
    color_map = {"Left": COLOR_LEFT, "Right": COLOR_RIGHT, "?": COLOR_UNK}
    h, w = out.shape[:2]
    for item in parsed:
        color = color_map.get(item["label"], COLOR_UNK)
        draw_hand(out, item["landmarks"], color)
        coords = item["coords"]
        x0 = int(coords[:, 0].min() * w)
        y0 = int(coords[:, 1].min() * h) - 8
        put_label(out, item["label"].upper(), (x0, max(y0, 18)),
                  color=(0, 0, 0), bg=color, scale=0.55)

    # Build feature vector
    feat = None
    slot_info = ""
    if len(parsed) >= 2:
        if mode == "handedness":
            left = next((p["coords"] for p in parsed if p["label"] == "Left"), None)
            right = next((p["coords"] for p in parsed if p["label"] == "Right"), None)
            if left is not None and right is not None:
                feat = make_features(left, right)
                slot_info = "slots: Left→slot1, Right→slot2 (handedness)"
            else:
                coords_two = [p["coords"] for p in parsed[:2]]
                coords_two.sort(key=lambda c: c[:, 0].mean())
                feat = make_features(coords_two[0], coords_two[1])
                slot_info = "slots: x-sort (handedness ambiguous)"
        else:
            coords_two = [p["coords"] for p in parsed[:2]]
            coords_two.sort(key=lambda c: c[:, 0].mean())
            feat = make_features(coords_two[0], coords_two[1])
            slot_info = "slots: leftmost→slot1, rightmost→slot2 (x-sort)"
    else:
        feat = make_features_single_hand(parsed[0]["coords"])
        slot_info = "single hand (zero-pad slot2)"

    scores = classifier.predict(feat)
    top3 = classifier.topk(scores, 3)
    chosen = top3[0][0] if top3 else "—"
    info = f"{slot_info} | dx={feat[-2]:+.3f} dy={feat[-1]:+.3f}"
    return out, top3, chosen, info


# ───── HUD overlay ───────────────────────────────────────────────────────────
def overlay_hud(img, top3, chosen, info, mode, fps, mirrored):
    h, w = img.shape[:2]
    # Top bar
    cv2.rectangle(img, (0, 0), (w, 34), (0, 0, 0), -1)
    put_label(img, f"mode={mode}  mirror={'on' if mirrored else 'off'}  fps={fps:.1f}",
              (8, 24), color=(255, 255, 255), bg=(0, 0, 0), scale=0.55)

    # Bottom strip
    cv2.rectangle(img, (0, h - 100), (w, h), (0, 0, 0), -1)
    put_label(img, f"PRED: {chosen}", (8, h - 72),
              color=(0, 255, 120), bg=(0, 0, 0), scale=1.0)
    for i, (lbl, sc) in enumerate(top3):
        put_label(img, f"{i+1}. {lbl:<8} {sc*100:5.1f}%",
                  (8, h - 42 + i * 18), scale=0.5)
    put_label(img, info, (max(w // 3, 260), h - 8), scale=0.45,
              color=(200, 200, 200), bg=(0, 0, 0))


# ───── Runners ───────────────────────────────────────────────────────────────
def run_webcam(args, classifier):
    cap = cv2.VideoCapture(args.camera)
    if not cap.isOpened():
        print(f"[FATAL] Tidak bisa buka kamera {args.camera}")
        return
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)

    detector = make_hand_detector()
    mode = "handedness"
    mirrored = True
    prev_t = time.time()
    fps = 0.0
    snap_idx = 0

    print("\n[KEYS] q/ESC quit | m toggle mode | f toggle mirror | s snapshot\n")

    while True:
        ok, frame = cap.read()
        if not ok:
            break
        if mirrored:
            frame = cv2.flip(frame, 1)

        annotated, top3, chosen, info = process_frame(frame, detector, classifier, mode)

        now = time.time()
        dt = now - prev_t
        if dt > 0:
            fps = 0.9 * fps + 0.1 * (1.0 / dt)
        prev_t = now

        overlay_hud(annotated, top3, chosen, info, mode, fps, mirrored)
        cv2.imshow("BISINDO Alphabet Tester", annotated)

        key = cv2.waitKey(1) & 0xFF
        if key in (ord('q'), 27):
            break
        elif key == ord('m'):
            mode = "xsort" if mode == "handedness" else "handedness"
            print(f"[MODE] → {mode}")
        elif key == ord('f'):
            mirrored = not mirrored
        elif key == ord('s'):
            out_path = ML_DIR / f"snapshot_bisindo_{snap_idx:03d}.png"
            cv2.imwrite(str(out_path), annotated)
            print(f"[SNAP] saved {out_path}")
            snap_idx += 1

    cap.release()
    cv2.destroyAllWindows()
    detector.close()


def run_image(args, classifier):
    img_path = Path(args.image)
    img = cv2.imread(str(img_path))
    if img is None:
        print(f"[FATAL] Tidak bisa baca image: {img_path}")
        return
    detector = make_hand_detector()
    for mode in ("handedness", "xsort"):
        annotated, top3, chosen, info = process_frame(img, detector, classifier, mode)
        overlay_hud(annotated, top3, chosen, info, mode, 0.0, False)
        print(f"\n=== {img_path.name} [mode={mode}] ===")
        print(f"  info : {info}")
        print(f"  pred : {chosen}")
        for i, (lbl, sc) in enumerate(top3):
            print(f"  top{i+1}: {lbl:<8} {sc*100:5.2f}%")
        out_path = img_path.with_name(f"{img_path.stem}_pred_{mode}.png")
        cv2.imwrite(str(out_path), annotated)
        print(f"  saved: {out_path}")
    detector.close()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default=str(DEFAULT_MODEL))
    ap.add_argument("--labels", default=str(DEFAULT_LABELS))
    ap.add_argument("--camera", type=int, default=0)
    ap.add_argument("--image", default=None)
    args = ap.parse_args()

    model_path = Path(args.model)
    labels_path = Path(args.labels)
    if not model_path.exists():
        print(f"[FATAL] Model tidak ditemukan: {model_path}")
        sys.exit(1)
    if not labels_path.exists():
        print(f"[FATAL] Labels tidak ditemukan: {labels_path}")
        sys.exit(1)

    classifier = AlphabetClassifier(model_path, labels_path)
    if args.image:
        run_image(args, classifier)
    else:
        run_webcam(args, classifier)


if __name__ == "__main__":
    main()
