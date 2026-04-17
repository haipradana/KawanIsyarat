#!/usr/bin/env python3
"""
kaggle_bisindo_wl.py — v3 (final, siap deploy)
================================================
Pipeline WL-BISINDO di Kaggle Notebook → TFLite untuk Flutter.

Arsitektur 1st-place Kaggle ASL Signs, diadaptasi untuk BISINDO:
  ✓ 98 floats/frame — hands + nose + shoulders + ears + elbows (konteks posisi & sudut lengan)
  ✓ Std-normalized per sequence (scale-invariant, NaN-safe)
  ✓ Temporal derivatives: position + velocity + acceleration → 294 floats
  ✓ Conv1DBlock + ECA + TransformerBlock (proven #1)
  ✓ Causal depthwise conv (kernel=11 for 30-frame sequence)

Feature vector layout (98 floats per frame):
  [0:42]   = Tangan KANAN  21×(x,y) nose-centered
  [42:84]  = Tangan KIRI   21×(x,y) nose-centered
  [84:86]  = nose          (x,y) nose-centered → selalu (0,0)
  [86:88]  = left shoulder (x,y) nose-centered
  [88:90]  = right shoulder(x,y) nose-centered
  [90:92]  = left ear      (x,y) nose-centered
  [92:94]  = right ear     (x,y) nose-centered
  [94:96]  = left elbow    (x,y) nose-centered  ← BARU: sudut lengan
  [96:98]  = right elbow   (x,y) nose-centered  ← BARU: sudut lengan

  Kenapa ears penting?
  → "Tuli" = tangan dekat telinga. Model butuh tahu DIMANA telinga
    relatif ke hidung, agar bisa korelasikan posisi tangan.
  → Sama untuk "Dengar", dll.

Normalisasi:
  1. Nose-centered: semua coords -= nose_position
  2. Per-sequence std normalization: x = (x - mean) / std
     → scale-invariant (jarak kamera, ukuran tubuh)
     → NaN-safe (nanmean/nanstd, lalu NaN→0)

Training derivatives (dihitung saat training, bukan extraction):
  position:     98 floats (raw)
  velocity:     98 floats (dx = x[t] - x[t-1])
  acceleration: 98 floats (dx2 = x[t] - x[t-2])
  Total input model: 98 × 3 = 294 per frame

Split: Leave-One-Signer-Out (LOSO)
  Train: signer 0,1,2  |  Val: signer 3  |  Test: signer 4

Cara pakai Kaggle Notebook:
  Cell 0:  !pip install mediapipe==0.9.3.0 -q   → Restart kernel
  Cell 1:  sanity_check()
  Cell 2:  stats = run_pipeline()
  Cell 3:  X_tr,y_tr, X_v,y_v, X_te,y_te, lm = load_dataset_for_training()
  Cell 4:  model, hist = train_model(X_tr,y_tr, X_v,y_v, X_te,y_te, lm)
  Cell 5:  convert_to_tflite(model, X_repr=X_tr[:100])
"""

# ── Imports ───────────────────────────────────────────────────────────────────
import json
import re
import subprocess
import sys
from pathlib import Path

import cv2
import numpy as np

# ── MediaPipe API detection ───────────────────────────────────────────────────
# v4: Prioritize Tasks API (0.10+) over solutions API (0.9.x)
# Tasks API = same as Flutter hand_landmarker plugin → training/inference consistent

def _detect_mp_api() -> str:
    """Detect which MediaPipe API is available. Returns 'tasks' or 'solutions'."""
    import mediapipe as mp
    if hasattr(mp, 'tasks'):
        try:
            from mediapipe.tasks.python import vision as _v
            _ = _v.HandLandmarker
            return "tasks"
        except (ImportError, AttributeError):
            pass
    try:
        _ = mp.solutions.hands
        return "solutions"
    except AttributeError:
        pass
    try:
        from mediapipe import solutions as _s
        _ = _s.hands
        return "solutions_alt"
    except (ImportError, AttributeError):
        pass
    raise ImportError("mediapipe tidak tersedia. pip install mediapipe>=0.10")

MP_API = _detect_mp_api()

# ── Paths ─────────────────────────────────────────────────────────────────────
VIDEO_DIR  = Path("/kaggle/input/wl-bisindo")
OUT_DIR    = Path("/kaggle/working/dataset")
LABELS_OUT = Path("/kaggle/working/bisindo_wl_labels.json")
MODEL_OUT  = Path("/kaggle/working/bisindo_wl_model.keras")
TFLITE_OUT = Path("/kaggle/working/bisindo_wl_model.tflite")
TASK_DIR   = Path("/kaggle/working")  # untuk simpan .task files

# ── Constants ─────────────────────────────────────────────────────────────────
SEQUENCE_LEN = 30
FEATURE_DIM  = 98    # 42+42+14 (hands + 7 pose anchors: nose+shoulder+ear+elbow)

# Pose landmark indices
POSE_NOSE       = 0
POSE_L_EAR      = 7
POSE_R_EAR      = 8
POSE_L_SHOULDER = 11
POSE_R_SHOULDER = 12
POSE_L_ELBOW    = 13   # BARU: siku kiri
POSE_R_ELBOW    = 14   # BARU: siku kanan
POSE_ANCHOR_IDX = [POSE_NOSE, POSE_L_SHOULDER, POSE_R_SHOULDER,
                   POSE_L_EAR, POSE_R_EAR,
                   POSE_L_ELBOW, POSE_R_ELBOW]  # 7 anchors × 2 = 14 floats

# ── FIVE-LABEL MODE ───────────────────────────────────────────────────────────
# Set True untuk train model 5 kelas dulu (lebih cepat, lebih akurat, demo-ready)
# Set False untuk train semua 28 kelas
FIVE_LABELS_MODE = True

# 5 label terpilih: paling berguna untuk komunikasi Tuli↔Dengar + visually distinct
FIVE_LABEL_SET = {"saya", "terima_kasih", "tuli", "maaf", "dengar"}

# ── Label mapping WL-BISINDO (32 kelas total) ─────────────────────────────────
BISINDO_LABELS = {
    0 : "air",          1 : "belajar",     2 : "cari",
    3 : "hari",         4 : "ingat",       5 : "lagi",
    6 : "maaf",         7 : "makan",       8 : "motor",
    9 : "saya",         10: "terima_kasih",11: "tuli",
    12: "apa",          13: "siapa",       14: "kapan",
    15: "di_mana",      16: "mengapa",     17: "bagaimana",
    18: "merah",        19: "kuning",      20: "hijau",
    21: "hitam",        22: "dengar",      23: "berangkat",
    24: "datang",       25: "teman",       26: "keluarga",
    27: "rumah",        28: "pagi",        29: "siang",
    30: "sore",         31: "malam",
}

# Kelas yang selalu dieksklusi (data buruk):
EXCLUDED_LABELS = {"cari", "apa", "berangkat", "keluarga"}

if FIVE_LABELS_MODE:
    # Hanya 5 label, eksklusi semua yang lain
    ACTIVE_LABELS = {lid: name for lid, name in BISINDO_LABELS.items()
                     if name in FIVE_LABEL_SET}
else:
    ACTIVE_LABELS = {lid: name for lid, name in BISINDO_LABELS.items()
                     if name not in EXCLUDED_LABELS}

NUM_CLASSES = len(ACTIVE_LABELS)
print(f"[Config] MediaPipe API: {MP_API} | Mode: {'5-label' if FIVE_LABELS_MODE else '28-label'} | Classes: {NUM_CLASSES}")


# ═════════════════════════════════════════════════════════════════════════════
# FEATURE EXTRACTION
# ═════════════════════════════════════════════════════════════════════════════

def _anatomical_is_right(landmarks) -> bool:
    """
    Tentukan handedness dari geometri palm — API-agnostic.
    Konsisten antara solutions API, Tasks API, dan Flutter hand_landmarker.

    Tidak bergantung pada label "Right"/"Left" dari API (berbeda antar versi
    dan bergantung pada asumsi mirroring kamera yang berbeda-beda).
    """
    w   = landmarks[0]   # wrist
    i5  = landmarks[5]   # index MCP
    p17 = landmarks[17]  # pinky MCP
    t4  = landmarks[4]   # thumb tip
    p20 = landmarks[20]  # pinky tip

    # Cross product (wrist→index_MCP) × (wrist→pinky_MCP)
    cross_z = (i5.x - w.x) * (p17.y - w.y) - (i5.y - w.y) * (p17.x - w.x)
    thumb_vs_pinky = t4.x - p20.x

    return (cross_z >= 0 and thumb_vs_pinky <= 0) or (cross_z < 0 and thumb_vs_pinky > 0)


def extract_features_from_frame(hand_result, pose_result) -> np.ndarray:
    """
    Satu frame MediaPipe → 98-float feature vector (nose-centered, RAW).
    Mendukung KEDUA API: solutions (0.9.x) dan Tasks (0.10.x).

    Handedness: pakai _anatomical_is_right (API-agnostic) agar konsisten
    dengan flutter hand_landmarker dan test_video.py.

    Layout:
      [0:42]   right hand 21×(x,y) nose-centered
      [42:84]  left hand  21×(x,y) nose-centered
      [84:86]  nose (0,0 setelah centering)
      [86:88]  left shoulder nose-centered
      [88:90]  right shoulder nose-centered
      [90:92]  left ear nose-centered
      [92:94]  right ear nose-centered
      [94:96]  left elbow nose-centered
      [96:98]  right elbow nose-centered
    """
    out = np.full(FEATURE_DIM, np.nan, dtype=np.float32)
    nose_x, nose_y = 0.5, 0.5

    # ── Solutions API (mediapipe 0.9.x) ──────────────────────────────────────
    if MP_API in ("solutions", "solutions_alt"):
        if pose_result.pose_landmarks:
            lm = pose_result.pose_landmarks.landmark
            nose_x, nose_y = lm[POSE_NOSE].x, lm[POSE_NOSE].y
            for i, idx in enumerate(POSE_ANCHOR_IDX):
                out[84 + i*2]     = lm[idx].x - nose_x
                out[84 + i*2 + 1] = lm[idx].y - nose_y

        if hand_result.multi_hand_landmarks is None:
            return out
        for hand_lm in hand_result.multi_hand_landmarks:
            is_right = _anatomical_is_right(hand_lm.landmark)
            base = 0 if is_right else 42
            for j, lm in enumerate(hand_lm.landmark):
                out[base + j*2]     = lm.x - nose_x
                out[base + j*2 + 1] = lm.y - nose_y

    # ── Tasks API (mediapipe 0.10+) ───────────────────────────────────────────
    else:
        if pose_result.pose_landmarks:
            lm = pose_result.pose_landmarks[0]
            nose_x, nose_y = lm[POSE_NOSE].x, lm[POSE_NOSE].y
            for i, idx in enumerate(POSE_ANCHOR_IDX):
                out[84 + i*2]     = lm[idx].x - nose_x
                out[84 + i*2 + 1] = lm[idx].y - nose_y

        if not hand_result.hand_landmarks:
            return out
        for hand_lm in hand_result.hand_landmarks:
            is_right = _anatomical_is_right(hand_lm)
            base = 0 if is_right else 42
            for j, lm in enumerate(hand_lm):
                out[base + j*2]     = lm.x - nose_x
                out[base + j*2 + 1] = lm.y - nose_y

    return out


def normalize_sequence_std(seq: np.ndarray) -> np.ndarray:
    """
    Per-sequence std normalization (seperti 1st place Kaggle ASL).
    
    x = (x - nanmean) / nanstd
    NaN → 0 setelah normalisasi.
    
    Kenapa ini lebih baik dari shoulder-width:
      - Scale-invariant terhadap jarak kamera DAN ukuran tubuh
      - Statistik dari semua frame → lebih stabil
      - NaN-safe secara alami
    
    Input/output: (SEQUENCE_LEN, FEATURE_DIM)
    """
    mean = np.nanmean(seq)
    std  = np.nanstd(seq)

    if std < 1e-6:
        std = 1.0    # semua nilai konstan/NaN → jangan scale

    seq = (seq - mean) / std
    seq = np.nan_to_num(seq, nan=0.0, posinf=0.0, neginf=0.0)

    return seq.astype(np.float32)


def _init_tasks_detectors():
    """
    Buat HandLandmarker + PoseLandmarker (Tasks API 0.10+).
    Download .task files jika belum ada.
    """
    import urllib.request
    from mediapipe.tasks import python as mp_python
    from mediapipe.tasks.python import vision
    from mediapipe.tasks.python.core.base_options import BaseOptions

    TASK_DIR.mkdir(parents=True, exist_ok=True)
    hand_path = TASK_DIR / "hand_landmarker.task"
    pose_path = TASK_DIR / "pose_landmarker_lite.task"

    for url, path in [
        ("https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task", hand_path),
        ("https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/latest/pose_landmarker_lite.task", pose_path),
    ]:
        if not path.exists():
            print(f"  Downloading {path.name} ...")
            urllib.request.urlretrieve(url, path)
            print(f"  ✅ {path.name}")

    hand_det = vision.HandLandmarker.create_from_options(
        vision.HandLandmarkerOptions(
            base_options=BaseOptions(model_asset_path=str(hand_path)),
            running_mode=vision.RunningMode.IMAGE,
            num_hands=2,
            min_hand_detection_confidence=0.3,
        )
    )
    pose_det = vision.PoseLandmarker.create_from_options(
        vision.PoseLandmarkerOptions(
            base_options=BaseOptions(model_asset_path=str(pose_path)),
            running_mode=vision.RunningMode.IMAGE,
            min_pose_detection_confidence=0.3,
        )
    )
    return hand_det, pose_det


def _process_frame_tasks(rgb: np.ndarray, hand_det, pose_det):
    """Process single RGB frame with Tasks API detectors."""
    import mediapipe as mp
    mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
    return hand_det.detect(mp_image), pose_det.detect(mp_image)


def extract_video_sequence(video_path: str, hands, pose) -> np.ndarray:
    """
    Satu video MP4 → (SEQUENCE_LEN, 98) float32.
    Uniform subsample ke 30 frame, lalu std-normalize per sequence.
    Mendukung solutions API dan Tasks API.
    """
    cap   = cv2.VideoCapture(str(video_path))
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

    if total <= 0:
        cap.release()
        return np.zeros((SEQUENCE_LEN, FEATURE_DIM), dtype=np.float32)

    indices = np.linspace(0, total - 1, SEQUENCE_LEN, dtype=int)
    seq     = []

    for fi in indices:
        cap.set(cv2.CAP_PROP_POS_FRAMES, int(fi))
        ret, frame = cap.read()
        if not ret:
            seq.append(np.full(FEATURE_DIM, np.nan, dtype=np.float32))
            continue

        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)

        if MP_API in ("solutions", "solutions_alt"):
            h_result = hands.process(rgb)
            p_result = pose.process(rgb)
        else:
            h_result, p_result = _process_frame_tasks(rgb, hands, pose)

        seq.append(extract_features_from_frame(h_result, p_result))

    cap.release()

    while len(seq) < SEQUENCE_LEN:
        seq.append(np.full(FEATURE_DIM, np.nan, dtype=np.float32))

    raw = np.array(seq[:SEQUENCE_LEN], dtype=np.float32)
    return normalize_sequence_std(raw)


# ═════════════════════════════════════════════════════════════════════════════
# SANITY CHECK
# ═════════════════════════════════════════════════════════════════════════════

def sanity_check():
    """Verifikasi dataset tersedia dan tampilkan distribusi."""
    print("\n🔧  Sanity Check — WL-BISINDO v3\n")
    print(f"  {'✅' if VIDEO_DIR.exists() else '❌'}  VIDEO_DIR : {VIDEO_DIR}")

    if not VIDEO_DIR.exists():
        input_root = Path("/kaggle/input")
        if input_root.exists():
            print(f"\n  📂  Isi /kaggle/input/:")
            for d in sorted(input_root.iterdir()):
                n = len(list(d.rglob("*.mp4")))
                print(f"       {d.name}  ({n} mp4)")
        print("\n  ⚠️  Sesuaikan VIDEO_DIR di atas!")
        return

    videos = list(VIDEO_DIR.rglob("*.mp4"))
    parsed = _parse_videos(videos)

    print(f"\n  Total video    : {len(videos)}")
    print(f"  Parsed OK      : {len(parsed)}")

    if not parsed:
        print(f"  ❌  Nama file tidak match pola signer{{N}}_label{{N}}_sample{{N}}.mp4")
        if videos:
            print(f"  Contoh: {videos[0].name}")
        return

    signers = sorted(set(p["signer"] for p in parsed))
    labels  = sorted(set(p["label"]  for p in parsed))

    print(f"  Signer         : {signers}")
    print(f"  Kelas          : {len(labels)}\n")

    print(f"  {'Label':<17} {'Total':>5}  {'s0':>3} {'s1':>3} {'s2':>3} {'s3':>3} {'s4':>3}")
    print(f"  {'─'*43}")
    for lid in labels:
        name = BISINDO_LABELS.get(lid, f"?{lid}")
        excl = " ❌" if name in EXCLUDED_LABELS else ""
        total = sum(1 for p in parsed if p["label"] == lid)
        per_s = [sum(1 for p in parsed if p["label"] == lid and p["signer"] == s)
                 for s in range(5)]
        print(f"  [{lid:2d}] {name:<13} {total:>3}   "
              f"{per_s[0]:>3} {per_s[1]:>3} {per_s[2]:>3} {per_s[3]:>3} {per_s[4]:>3}{excl}")

    n_tr = sum(1 for p in parsed if p["signer"] in [0,1,2])
    n_v  = sum(1 for p in parsed if p["signer"] == 3)
    n_te = sum(1 for p in parsed if p["signer"] == 4)
    print(f"\n  🔀  LOSO split: train={n_tr}  val={n_v}  test={n_te}")
    print(f"  📐  Feature: {FEATURE_DIM} × 3 = {FEATURE_DIM*3}/frame")
    print(f"  ❌  Excluded: {EXCLUDED_LABELS}")
    print(f"  ✅  Active ({NUM_CLASSES} kelas): {sorted(set(ACTIVE_LABELS.values()))}")


# ═════════════════════════════════════════════════════════════════════════════
# VISUALISASI MEDIAPIPE — cek skeleton sebelum/sesudah training
# ═════════════════════════════════════════════════════════════════════════════

# Koneksi tulang tangan MediaPipe (21 landmarks)
_HAND_CONNECTIONS = [
    (0,1),(1,2),(2,3),(3,4),           # ibu jari
    (0,5),(5,6),(6,7),(7,8),           # telunjuk
    (0,9),(9,10),(10,11),(11,12),      # tengah
    (0,13),(13,14),(14,15),(15,16),    # manis
    (0,17),(17,18),(18,19),(19,20),    # kelingking
    (5,9),(9,13),(13,17),              # palm
]

def visualize_mediapipe(
    n_labels: int = None,
    n_frames: int = 5,
    signer_id: int = 0,
    sample_id: int = 0,
):
    """
    Visualisasi hasil MediaPipe skeleton pada sample video.
    Jalankan di Kaggle notebook SEBELUM training untuk verifikasi deteksi.

    Args:
        n_labels : berapa label yang divisualisasikan (None = semua active)
        n_frames : berapa frame per video yang ditampilkan
        signer_id: signer yang dipakai (0–4)
        sample_id: index sample (0-based)

    Usage (di Kaggle cell):
        visualize_mediapipe()                   # semua 5 label, 5 frame
        visualize_mediapipe(n_labels=2)         # hanya 2 label pertama
        visualize_mediapipe(n_frames=8)         # 8 frame per video
    """
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    import matplotlib.patches as mpatches

    active_names = sorted(set(ACTIVE_LABELS.values()))
    if n_labels is not None:
        active_names = active_names[:n_labels]

    n_labels_show = len(active_names)
    fig, axes = plt.subplots(
        n_labels_show, n_frames,
        figsize=(n_frames * 2.5, n_labels_show * 2.8),
    )
    if n_labels_show == 1:
        axes = axes[np.newaxis, :]
    fig.suptitle(
        f"MediaPipe Skeleton Check — {MP_API} API\n"
        f"signer={signer_id}, sample={sample_id}",
        fontsize=11, fontweight='bold', y=1.01,
    )

    # Setup detectors
    if MP_API in ("solutions", "solutions_alt"):
        import mediapipe as mp
        try:
            sol = mp.solutions
        except AttributeError:
            from mediapipe import solutions as sol
        hands_ctx = sol.hands.Hands(static_image_mode=True, max_num_hands=2,
                                    min_detection_confidence=0.3)
        pose_ctx  = sol.pose.Pose(static_image_mode=True,
                                  min_detection_confidence=0.3)
        hands_ctx.__enter__()
        pose_ctx.__enter__()
        def _detect(rgb):
            return hands_ctx.process(rgb), pose_ctx.process(rgb)
        use_tasks = False
    else:
        hand_det, pose_det = _init_tasks_detectors()
        def _detect(rgb):
            return _process_frame_tasks(rgb, hand_det, pose_det)
        use_tasks = True

    def _draw_skeleton(ax, frame_rgb, h_result, p_result, title):
        """Draw frame + skeleton overlay."""
        ax.imshow(frame_rgb)
        H, W = frame_rgb.shape[:2]

        # ── Pose landmarks ────────────────────────────────────────────────
        nose_x_px, nose_y_px = W // 2, H // 2
        if MP_API in ("solutions", "solutions_alt"):
            if p_result.pose_landmarks:
                lm = p_result.pose_landmarks.landmark
                for idx in POSE_ANCHOR_IDX:
                    px, py = lm[idx].x * W, lm[idx].y * H
                    ax.plot(px, py, 'o', color='#00FF88', ms=4, zorder=3)
                nose_x_px = lm[0].x * W
                nose_y_px = lm[0].y * H
        else:
            if p_result.pose_landmarks:
                lm = p_result.pose_landmarks[0]
                for idx in POSE_ANCHOR_IDX:
                    px, py = lm[idx].x * W, lm[idx].y * H
                    ax.plot(px, py, 'o', color='#00FF88', ms=4, zorder=3)
                nose_x_px = lm[0].x * W
                nose_y_px = lm[0].y * H

        # Mark nose with white ring
        ax.plot(nose_x_px, nose_y_px, 'o', color='white', ms=6,
                markerfacecolor='none', markeredgewidth=1.5, zorder=4)

        # ── Hand landmarks ────────────────────────────────────────────────
        colors = {'right': '#1D9E75', 'left': '#4FC3F7'}

        def _draw_hand(landmarks_list):
            for lm_list in landmarks_list:
                if MP_API in ("solutions", "solutions_alt"):
                    pts = [(l.x * W, l.y * H) for l in lm_list.landmark]
                else:
                    pts = [(l.x * W, l.y * H) for l in lm_list]
                is_r = _anatomical_is_right(
                    lm_list.landmark if MP_API in ("solutions","solutions_alt") else lm_list
                )
                col = colors['right'] if is_r else colors['left']
                for a, b in _HAND_CONNECTIONS:
                    ax.plot([pts[a][0], pts[b][0]], [pts[a][1], pts[b][1]],
                            '-', color=col, lw=1.2, alpha=0.8, zorder=2)
                for px, py in pts:
                    ax.plot(px, py, 'o', color=col, ms=3, zorder=3)
                # Wrist label
                wx, wy = pts[0]
                ax.text(wx + 4, wy - 4, 'R' if is_r else 'L',
                        color=col, fontsize=7, fontweight='bold', zorder=5)

        if MP_API in ("solutions", "solutions_alt"):
            if h_result.multi_hand_landmarks:
                _draw_hand(h_result.multi_hand_landmarks)
        else:
            if h_result.hand_landmarks:
                _draw_hand(h_result.hand_landmarks)

        ax.set_title(title, fontsize=7.5, pad=2)
        ax.axis('off')

    # ── Loop labels ───────────────────────────────────────────────────────────
    for row, label_name in enumerate(active_names):
        # Cari video file
        pattern = f"signer{signer_id}_*_sample{sample_id:02d}.mp4"
        matches = list(VIDEO_DIR.rglob(pattern))
        # Filter ke label yang benar
        label_id = next((k for k, v in BISINDO_LABELS.items() if v == label_name), None)
        if label_id is not None:
            matches = [m for m in VIDEO_DIR.rglob("*.mp4")
                       if re.match(rf"signer{signer_id}_label{label_id}_sample\d+", m.stem)]

        if not matches:
            for col in range(n_frames):
                axes[row, col].text(0.5, 0.5, f'{label_name}\nnot found',
                                    ha='center', va='center', transform=axes[row, col].transAxes)
                axes[row, col].axis('off')
            continue

        video_path = matches[0]
        cap   = cv2.VideoCapture(str(video_path))
        total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

        if total <= 0:
            cap.release()
            continue

        frame_indices = np.linspace(0, total - 1, n_frames, dtype=int)
        for col, fi in enumerate(frame_indices):
            cap.set(cv2.CAP_PROP_POS_FRAMES, int(fi))
            ret, frame = cap.read()
            if not ret:
                axes[row, col].axis('off')
                continue
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            h_result, p_result = _detect(rgb)

            title = f"{label_name} | f{fi}"
            _draw_skeleton(axes[row, col], rgb, h_result, p_result, title)

        cap.release()

    # Cleanup
    if not use_tasks:
        hands_ctx.__exit__(None, None, None)
        pose_ctx.__exit__(None, None, None)

    # Legend
    patches = [
        mpatches.Patch(color='#1D9E75', label='Right hand (anatomical)'),
        mpatches.Patch(color='#4FC3F7', label='Left hand (anatomical)'),
        mpatches.Patch(color='#00FF88', label='Pose anchors'),
    ]
    fig.legend(handles=patches, loc='lower center', ncol=3,
               fontsize=8, bbox_to_anchor=(0.5, -0.02))
    plt.tight_layout()
    plt.savefig('/kaggle/working/mediapipe_check.png', dpi=100,
                bbox_inches='tight', facecolor='#1a1a2e')
    plt.show()
    print(f"\n✅  Disimpan: /kaggle/working/mediapipe_check.png")


def visualize_features(label_name: str = None, signer_id: int = 0):
    """
    Visualisasi 98-float feature vector sebagai heatmap.
    Cek apakah tangan kanan/kiri terdeteksi dengan benar setelah ekstraksi.

    Usage:
        visualize_features('terima_kasih')
        visualize_features('tuli', signer_id=1)
    """
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt

    if label_name is None:
        label_name = sorted(set(ACTIVE_LABELS.values()))[0]

    # Cari semua npy dari label ini
    folder = OUT_DIR / label_name
    if not folder.exists():
        print(f"❌ Belum ada data untuk '{label_name}'. Jalankan run_pipeline() dulu.")
        return

    npys = sorted(folder.glob(f"seq_s{signer_id}_*.npy"))
    if not npys:
        print(f"❌ Tidak ada .npy untuk signer={signer_id} label={label_name}")
        return

    n_show = min(5, len(npys))
    fig, axes = plt.subplots(1, n_show, figsize=(n_show * 3.5, 3.5))
    if n_show == 1:
        axes = [axes]

    fig.suptitle(
        f"Feature Heatmap: '{label_name}' signer={signer_id}\n"
        f"Baris=frame(30), Kolom=feature(98)\n"
        f"  [0:42]=RightHand  [42:84]=LeftHand  [84:94]=PoseAnchors  [94:98]=Elbows",
        fontsize=9, y=1.05,
    )

    for ax, npy_path in zip(axes, npys[:n_show]):
        seq = np.load(str(npy_path))   # (30, 98)

        im = ax.imshow(seq, aspect='auto', cmap='RdBu_r',
                       vmin=-2, vmax=2, interpolation='nearest')
        ax.set_title(npy_path.stem, fontsize=7)
        ax.set_xlabel('Feature dim (98)', fontsize=7)
        ax.set_ylabel('Frame (30)', fontsize=7)

        # Grid lines untuk batasi right/left/pose/elbow
        for xline in [42, 84, 94]:
            ax.axvline(xline, color='yellow', lw=0.8, alpha=0.7)

        # Label zona
        for x, label in [(21, 'R'), (63, 'L'), (89, 'P')]:
            ax.text(x, -1.5, label, color='yellow', fontsize=8,
                    ha='center', va='bottom', fontweight='bold')

        # Tunjukkan berapa frame dengan tangan terdeteksi
        has_right = np.any(seq[:, 0:42] != 0, axis=1).sum()
        has_left  = np.any(seq[:, 42:84] != 0, axis=1).sum()
        ax.set_title(f"{npy_path.stem}\nR:{has_right}/30  L:{has_left}/30", fontsize=7)

    plt.colorbar(im, ax=axes[-1], fraction=0.046, pad=0.04, label='std-normalized')
    plt.tight_layout()
    plt.savefig(f'/kaggle/working/features_{label_name}.png', dpi=100,
                bbox_inches='tight', facecolor='#1a1a2e')
    plt.show()
    print(f"✅  Disimpan: /kaggle/working/features_{label_name}.png")
    print(f"   Right hand frames: {has_right}/30")
    print(f"   Left hand frames : {has_left}/30")


def _parse_videos(videos):
    parsed = []
    for v in videos:
        m = re.match(r"signer(\d+)_label(\d+)_sample(\d+)", v.stem)
        if m:
            parsed.append({
                "path"  : v,
                "signer": int(m.group(1)),
                "label" : int(m.group(2)),
                "sample": int(m.group(3)),
            })
    return parsed


# ═════════════════════════════════════════════════════════════════════════════
# PIPELINE: VIDEO → NPY
# ═════════════════════════════════════════════════════════════════════════════

def run_pipeline(min_hand_frames: int = 3) -> dict:
    """
    Proses semua WL-BISINDO video → .npy sequences.
    
    Setiap .npy: shape (30, 98) float32, std-normalized per sequence.
    Filename encode signer ID: seq_s{signer}_{num}.npy → untuk LOSO split.
    """
    videos = list(VIDEO_DIR.rglob("*.mp4"))
    parsed_all = _parse_videos(videos)
    if not parsed_all:
        raise FileNotFoundError(f"Tidak ada video valid di {VIDEO_DIR}")

    # Filter hanya active labels SEBELUM loop — tidak perlu iterasi 1600 video kalau 5-label mode
    active_names = set(ACTIVE_LABELS.values())
    active_label_ids = {lid for lid, name in BISINDO_LABELS.items() if name in active_names}
    parsed = [p for p in parsed_all if p["label"] in active_label_ids]

    mode_str = "5-label" if FIVE_LABELS_MODE else "28-label"
    print(f"\n🔄  Memproses {len(parsed)}/{len(parsed_all)} video → MediaPipe ({MP_API}) → npy  [{mode_str}]")
    print(f"   Active: {sorted(active_names)}\n")
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    stats   = {lid: {"total": 0, "saved": 0, "skip_nohand": 0, "skip_excl": 0}
               for lid in BISINDO_LABELS}
    counter = {lid: {} for lid in BISINDO_LABELS}

    def _run_pipeline_body(hands, pose):
        for i, item in enumerate(sorted(parsed,
                                        key=lambda x: (x["label"], x["signer"], x["sample"]))):
            lid = item["label"]
            sid = item["signer"]
            label_name = BISINDO_LABELS.get(lid, f"label{lid}")

            stats[lid]["total"] += 1

            save_dir = OUT_DIR / label_name
            save_dir.mkdir(parents=True, exist_ok=True)

            counter[lid].setdefault(sid, 0)

            seq = extract_video_sequence(str(item["path"]), hands, pose)

            # Validasi: tangan terdeteksi minimal min_hand_frames
            hand_active = np.any(seq[:, :84] != 0, axis=1).sum()
            if hand_active < min_hand_frames:
                stats[lid]["skip_nohand"] += 1
                continue

            # Final NaN guard
            if not np.all(np.isfinite(seq)):
                seq = np.nan_to_num(seq, nan=0.0)

            fname = save_dir / f"seq_s{sid}_{counter[lid][sid]:04d}.npy"
            np.save(str(fname), seq)
            counter[lid][sid] += 1
            stats[lid]["saved"] += 1

            if (i + 1) % 100 == 0 or i == 0:
                total_saved = sum(v["saved"] for v in stats.values())
                print(f"  [{i+1:4d}/{len(parsed)}]  "
                      f"{label_name:<15} signer={sid}  saved={total_saved}")

    # ── Run with correct API ──────────────────────────────────────────────────
    if MP_API in ("solutions", "solutions_alt"):
        import mediapipe as mp
        try:
            sol = mp.solutions
        except AttributeError:
            from mediapipe import solutions as sol
        with sol.hands.Hands(
            max_num_hands=2,
            min_detection_confidence=0.5,
            min_tracking_confidence=0.4,
        ) as hands, sol.pose.Pose(
            min_detection_confidence=0.4,
            min_tracking_confidence=0.4,
        ) as pose:
            _run_pipeline_body(hands, pose)
    else:
        # Tasks API — detectors don't use context manager
        hand_det, pose_det = _init_tasks_detectors()
        _run_pipeline_body(hand_det, pose_det)

    # Summary
    total_saved  = sum(v["saved"]       for v in stats.values())
    total_skip_h = sum(v["skip_nohand"] for v in stats.values())
    total_excl   = sum(v["skip_excl"]   for v in stats.values())

    print(f"\n{'═'*55}")
    print(f"  {'Label':<17} {'Saved':>5} {'NoHand':>7} {'Excl':>5}")
    print(f"{'─'*55}")
    for lid, s in stats.items():
        tag = " ❌" if BISINDO_LABELS[lid] in EXCLUDED_LABELS else ""
        print(f"  [{lid:2d}] {BISINDO_LABELS[lid]:<13} {s['saved']:>5} {s['skip_nohand']:>7} {s['skip_excl']:>5}{tag}")
    print(f"{'─'*55}")
    print(f"  {'TOTAL':<17} {total_saved:>5} {total_skip_h:>7} {total_excl:>5}")
    print(f"  Active classes: {NUM_CLASSES}")
    print(f"{'═'*55}")

    _build_label_map()
    return stats


def _build_label_map() -> dict:
    """Buat label map JSON hanya dari ACTIVE labels yang punya data."""
    label_to_index = {}
    for lid, name in ACTIVE_LABELS.items():
        folder = OUT_DIR / name
        if folder.exists() and len(list(folder.glob("seq_*.npy"))) > 0:
            label_to_index[name] = len(label_to_index)

    out = {
        "label_to_index" : label_to_index,
        "index_to_label" : {str(v): k for k, v in label_to_index.items()},
        "num_classes"    : len(label_to_index),
        "labels"         : list(label_to_index.keys()),
        "feature_dim"    : FEATURE_DIM,
        "sequence_len"   : SEQUENCE_LEN,
        "dataset"        : "WL-BISINDO",
        "normalization"  : "nose-centered + per-sequence std",
        "temporal_total" : FEATURE_DIM * 3,  # 294 saat training
    }
    with open(LABELS_OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2, ensure_ascii=False)
    print(f"\n✅  Label map ({len(label_to_index)} kelas) → {LABELS_OUT}")
    return out


# ═════════════════════════════════════════════════════════════════════════════
# LOAD DATASET (LOSO split)
# ═════════════════════════════════════════════════════════════════════════════

def load_dataset_for_training(
    train_signers=[0,1,2], val_signers=[3], test_signers=[4]
):
    """
    Load npy, split per signer.
    Returns: X_train, y_train, X_val, y_val, X_test, y_test, label_map
    """
    with open(LABELS_OUT, encoding="utf-8") as f:
        label_map = json.load(f)

    l2i = label_map["label_to_index"]
    all_signers = train_signers + val_signers + test_signers

    splits = {
        "train": (train_signers, [], []),
        "val"  : (val_signers,   [], []),
        "test" : (test_signers,  [], []),
    }

    for label_name in label_map["labels"]:
        folder = OUT_DIR / label_name
        if not folder.exists():
            continue
        idx = l2i[label_name]

        for npy_path in sorted(folder.glob("seq_s*.npy")):
            m = re.match(r"seq_s(\d+)_", npy_path.stem)
            if not m:
                continue
            sid = int(m.group(1))
            if sid not in all_signers:
                continue

            seq = np.load(str(npy_path))
            if not np.all(np.isfinite(seq)):
                continue

            for _, (signer_list, X_list, y_list) in splits.items():
                if sid in signer_list:
                    X_list.append(seq)
                    y_list.append(idx)
                    break

    X_train = np.array(splits["train"][1], dtype=np.float32)
    y_train = np.array(splits["train"][2], dtype=np.int32)
    X_val   = np.array(splits["val"][1],   dtype=np.float32)
    y_val   = np.array(splits["val"][2],   dtype=np.int32)
    X_test  = np.array(splits["test"][1],  dtype=np.float32)
    y_test  = np.array(splits["test"][2],  dtype=np.int32)

    print(f"\n📦  Dataset loaded:")
    print(f"  Train : {X_train.shape}  ({len(train_signers)} signer)")
    print(f"  Val   : {X_val.shape}  ({len(val_signers)} signer)")
    print(f"  Test  : {X_test.shape}  ({len(test_signers)} signer)")
    print(f"  Kelas : {label_map['num_classes']}")

    i2l = label_map["index_to_label"]
    print(f"\n  Distribusi (train):")
    for idx in sorted(set(y_train)):
        n   = int((y_train == idx).sum())
        bar = "█" * (n // 2)
        print(f"    [{idx:2d}] {i2l[str(idx)]:<15} {n:>3}  {bar}")

    return X_train, y_train, X_val, y_val, X_test, y_test, label_map


# ═════════════════════════════════════════════════════════════════════════════
# PREPROCESSING & AUGMENTATION
# ═════════════════════════════════════════════════════════════════════════════

def add_temporal_derivatives(X: np.ndarray) -> np.ndarray:
    """
    Position + velocity + acceleration.
    (N, 30, 98) → (N, 30, 294)

    Ini game-changer dari 1st place:
      - Model tidak hanya tahu "tangan di mana"
      - Tapi juga "tangan bergerak ke arah mana, seberapa cepat"
      - Contoh: "Tuli" vs "Dengar" — posisi mirip, gerakan beda
    """
    vel = np.zeros_like(X)
    acc = np.zeros_like(X)
    vel[:, 1:, :] = X[:, 1:, :] - X[:, :-1, :]   # dx/dt
    acc[:, 2:, :] = X[:, 2:, :] - X[:, :-2, :]    # dx/dt²
    return np.concatenate([X, vel, acc], axis=-1)


def augment_batch(X: np.ndarray, noise_std: float = 0.015) -> np.ndarray:
    """
    Online augmentation — dijalankan tiap epoch, setiap kali berbeda.

    Terinspirasi 1st place Kaggle ASL Signs + pengalaman SIBI alphabet:

    1. Gaussian noise                 (always)
    2. Time masking 0–4 frame         (always)
    3. Horizontal flip + hand swap    (50%) ← key: sama seperti SIBI, terbukti bagus
    4. Temporal stretch ±30%          (80%) ← dari kompetisi, paling impact untuk generalisasi
    5. Scale jitter ±10%              (50%)
    6. Spatial translate ±5%          (40%) ← dari kompetisi
    7. Time crop + re-pad             (30%)

    Feature layout (98 floats):
      [0:42]   right hand 21×(x,y)
      [42:84]  left hand  21×(x,y)
      [84:86]  nose       (x,y)
      [86:88]  left shoulder
      [88:90]  right shoulder
      [90:92]  left ear
      [92:94]  right ear
      [94:96]  left elbow
      [96:98]  right elbow
    """
    X = X.copy()
    N, T, D = X.shape

    # ── 1. Gaussian noise (hanya hands, bukan pose anchors) ───────────────────
    X[:, :, :84] += np.random.normal(0, noise_std, (N, T, 84)).astype(np.float32)

    # ── 2. Time masking (drop 0–4 consecutive frames → zero) ─────────────────
    for i in range(N):
        n_mask = np.random.randint(0, 5)
        if n_mask > 0:
            start = np.random.randint(0, max(1, T - n_mask))
            X[i, start:start + n_mask, :] = 0.0

    # ── 3. Horizontal flip + hand swap (50%) ──────────────────────────────────
    # Sama seperti augmentasi SIBI alfabet — flip kiri↔kanan.
    # Untuk sequences: swap slot tangan + negate semua x + swap pose anchors kiri↔kanan.
    #
    # Feature layout setelah flip:
    #   [0:42]  ← was left hand   (swap)
    #   [42:84] ← was right hand  (swap)
    #   [84]    ← nose x negated  (simetri)
    #   [86:88] ← was right shoulder (swap dengan [88:90])
    #   [88:90] ← was left shoulder  (swap dengan [86:88])
    #   [90:92] ← was right ear      (swap dengan [92:94])
    #   [92:94] ← was left ear       (swap dengan [90:92])
    #   [94:96] ← was right elbow    (swap dengan [96:98])
    #   [96:98] ← was left elbow     (swap dengan [94:96])
    flip_mask = np.random.rand(N) < 0.5
    if flip_mask.any():
        Xf = X[flip_mask].copy()

        # Swap right hand [0:42] ↔ left hand [42:84]
        tmp = Xf[:, :, 0:42].copy()
        Xf[:, :, 0:42]  = Xf[:, :, 42:84]
        Xf[:, :, 42:84] = tmp

        # Swap left shoulder [86:88] ↔ right shoulder [88:90]
        tmp = Xf[:, :, 86:88].copy()
        Xf[:, :, 86:88] = Xf[:, :, 88:90]
        Xf[:, :, 88:90] = tmp

        # Swap left ear [90:92] ↔ right ear [92:94]
        tmp = Xf[:, :, 90:92].copy()
        Xf[:, :, 90:92] = Xf[:, :, 92:94]
        Xf[:, :, 92:94] = tmp

        # Swap left elbow [94:96] ↔ right elbow [96:98]
        tmp = Xf[:, :, 94:96].copy()
        Xf[:, :, 94:96] = Xf[:, :, 96:98]
        Xf[:, :, 96:98] = tmp

        # Negate semua x-coordinates (even indices) → mirror horizontal
        Xf[:, :, 0::2] *= -1

        X[flip_mask] = Xf

    # ── 4. Temporal stretch ±30% (80% chance) — dari 1st place kompetisi ─────
    # Paling penting untuk generalisasi ke signer dengan kecepatan berbeda.
    # 0.7x = gesture lambat, 1.3x = gesture cepat, lalu resample balik ke T frames.
    speed_mask = np.random.rand(N) < 0.8
    for i in np.where(speed_mask)[0]:
        speed   = np.random.uniform(0.7, 1.3)
        new_len = max(8, int(T * speed))
        # Sample dari sequence asli dengan interpolasi linear
        src_t   = np.linspace(0, T - 1, new_len)
        lo      = np.clip(src_t.astype(int),     0, T - 1)
        hi      = np.clip(src_t.astype(int) + 1, 0, T - 1)
        frac    = (src_t - lo)[:, None]               # (new_len, 1)
        stretched = X[i][lo] * (1 - frac) + X[i][hi] * frac  # (new_len, D)
        # Resample stretched → T frames (uniform subsample)
        dst_t   = np.linspace(0, new_len - 1, T).astype(int)
        X[i]    = stretched[dst_t]

    # ── 5. Scale jitter ±10% pada tangan (50%) ────────────────────────────────
    scale_mask = np.random.rand(N) < 0.5
    if scale_mask.any():
        scales = np.random.uniform(0.90, 1.10,
                                   size=(scale_mask.sum(), 1, 1)).astype(np.float32)
        X[scale_mask, :, :84] *= scales

    # ── 6. Spatial translation ±5% (40%) — dari kompetisi ────────────────────
    # Simulates signer di posisi berbeda dalam frame
    translate_mask = np.random.rand(N) < 0.4
    if translate_mask.any():
        tx = np.random.uniform(-0.05, 0.05, (translate_mask.sum(), 1, 1)).astype(np.float32)
        ty = np.random.uniform(-0.05, 0.05, (translate_mask.sum(), 1, 1)).astype(np.float32)
        # Apply to hand x (even) and hand y (odd) coords
        X[translate_mask, :, 0:84:2] += tx  # all x in hands
        X[translate_mask, :, 1:84:2] += ty  # all y in hands

    # ── 7. Temporal crop + re-pad (30%) ──────────────────────────────────────
    # Potong 10–25% frame di awal/akhir → model tidak bergantung pada alignment
    crop_mask = np.random.rand(N) < 0.3
    for i in np.where(crop_mask)[0]:
        crop_frac  = np.random.uniform(0.10, 0.25)
        crop_frames = max(1, int(T * crop_frac))
        side = np.random.choice(['start', 'end', 'both'])
        if side == 'start':
            X[i] = np.concatenate([
                X[i, crop_frames:],
                np.zeros((crop_frames, D), dtype=np.float32)
            ])
        elif side == 'end':
            X[i] = np.concatenate([
                np.zeros((crop_frames, D), dtype=np.float32),
                X[i, :T - crop_frames]
            ])
        else:
            half = crop_frames // 2
            X[i] = np.concatenate([
                X[i, half: T - half],
                np.zeros((crop_frames, D), dtype=np.float32)
            ])[:T]

    return X


# ═════════════════════════════════════════════════════════════════════════════
# CUSTOM LAYERS — harus di module level agar Keras bisa serialize/deserialize
# ═════════════════════════════════════════════════════════════════════════════

import tensorflow as tf
from tensorflow.keras import layers

# Kompatibel TF 2.x lama (Kaggle) dan baru
try:
    _register = tf.keras.saving.register_keras_serializable
except AttributeError:
    try:
        _register = tf.keras.utils.register_keras_serializable
    except AttributeError:
        _register = lambda **kw: (lambda cls: cls)  # no-op fallback

@_register(package="bisindo")
class ECA(layers.Layer):
    """Efficient Channel Attention (dari 1st place ASL solution)."""
    def __init__(self, kernel_size=5, **kwargs):
        super().__init__(**kwargs)
        self.kernel_size = kernel_size
    def build(self, input_shape):
        self.conv = layers.Conv1D(1, self.kernel_size, padding="same", use_bias=False)
        super().build(input_shape)
    def call(self, x):
        attn = tf.reduce_mean(x, axis=1)          # (B, C)
        attn = tf.expand_dims(attn, -1)             # (B, C, 1)
        attn = self.conv(attn)                       # (B, C, 1)
        attn = tf.squeeze(attn, -1)                  # (B, C)
        attn = tf.nn.sigmoid(attn)[:, None, :]       # (B, 1, C)
        return x * attn
    def get_config(self):
        cfg = super().get_config()
        cfg["kernel_size"] = self.kernel_size
        return cfg

@_register(package="bisindo")
class CausalDWConv1D(layers.Layer):
    """Causal depthwise conv1d — sees only past frames."""
    def __init__(self, kernel_size=11, dilation_rate=1, **kwargs):
        super().__init__(**kwargs)
        self.kernel_size   = kernel_size
        self.dilation_rate = dilation_rate
    def build(self, input_shape):
        self.pad     = layers.ZeroPadding1D(
            (self.dilation_rate * (self.kernel_size - 1), 0))
        self.dw_conv = layers.DepthwiseConv1D(
            self.kernel_size, strides=1,
            dilation_rate=self.dilation_rate,
            padding='valid', use_bias=False)
        super().build(input_shape)
    def call(self, x):
        return self.dw_conv(self.pad(x))
    def get_config(self):
        cfg = super().get_config()
        cfg["kernel_size"]   = self.kernel_size
        cfg["dilation_rate"] = self.dilation_rate
        return cfg

# Dict untuk load_model
CUSTOM_OBJECTS = {"ECA": ECA, "CausalDWConv1D": CausalDWConv1D}


# ═════════════════════════════════════════════════════════════════════════════
# MODEL — 1st place Conv1D + ECA + Transformer (sized for BISINDO)
# ═════════════════════════════════════════════════════════════════════════════

def build_model(num_classes: int, input_dim: int = 294, seq_len: int = SEQUENCE_LEN):
    """
    Arsitektur terinspirasi 1st place ASL Kaggle solution (@hoyso48).
    Disesuaikan untuk WL-BISINDO (32 kelas, 1600 video):

    Original (250 kelas, 94k data):
      dim=192, kernel=17, 6×Conv1DBlock + 2×Transformer, 1.8M params

    Adapted (32 kelas, 1.6k data):
      dim=64, kernel=11, 4×Conv1DBlock + 2×Transformer, ~120k params
    """
    from tensorflow.keras import Model

    # ── Block builders ────────────────────────────────────────────────────────
    def conv1d_block(dim, ksize=11, drop_rate=0.2, expand_ratio=2):
        def apply(inputs):
            ch_in = inputs.shape[-1]
            x = layers.Dense(dim * expand_ratio, activation='swish')(inputs)
            x = CausalDWConv1D(ksize)(x)
            x = layers.BatchNormalization(momentum=0.95)(x)
            x = ECA()(x)
            x = layers.Dense(dim)(x)
            if drop_rate > 0:
                x = layers.Dropout(drop_rate, noise_shape=(None, 1, 1))(x)
            if ch_in == dim:
                x = layers.Add()([x, inputs])
            return x
        return apply

    def transformer_block(dim, num_heads=2, expand=2, drop_rate=0.2):
        def apply(inputs):
            x = layers.BatchNormalization(momentum=0.95)(inputs)
            x = layers.MultiHeadAttention(
                num_heads=num_heads,
                key_dim=dim // num_heads,
                dropout=drop_rate,
            )(x, x)
            x = layers.Dropout(drop_rate, noise_shape=(None, 1, 1))(x)
            x = layers.Add()([inputs, x])
            attn_out = x
            x = layers.BatchNormalization(momentum=0.95)(x)
            x = layers.Dense(dim * expand, activation='swish')(x)
            x = layers.Dense(dim)(x)
            x = layers.Dropout(drop_rate, noise_shape=(None, 1, 1))(x)
            x = layers.Add()([attn_out, x])
            return x
        return apply

    # ── Assemble model ────────────────────────────────────────────────────────
    DIM   = 64
    KSIZE = 11

    inp = layers.Input(shape=(seq_len, input_dim), name="input")

    x = layers.Dense(DIM, use_bias=False, name='stem_proj')(inp)
    x = layers.BatchNormalization(momentum=0.95, name='stem_bn')(x)

    # Stage 1
    x = conv1d_block(DIM, KSIZE, drop_rate=0.15)(x)
    x = conv1d_block(DIM, KSIZE, drop_rate=0.15)(x)
    x = transformer_block(DIM, num_heads=2, drop_rate=0.15)(x)

    # Stage 2
    x = conv1d_block(DIM, KSIZE, drop_rate=0.2)(x)
    x = conv1d_block(DIM, KSIZE, drop_rate=0.2)(x)
    x = transformer_block(DIM, num_heads=2, drop_rate=0.2)(x)

    # Head
    x   = layers.Dense(DIM * 2, activation='swish', name='head_proj')(x)
    x   = layers.GlobalAveragePooling1D(name='gap')(x)
    x   = layers.Dropout(0.4)(x)
    out = layers.Dense(num_classes, activation='softmax', name='classifier')(x)

    model = Model(inputs=inp, outputs=out, name="bisindo_wl_v3")
    return model


def _load_best_model():
    """Load model terbaik dengan custom_objects."""
    return tf.keras.models.load_model(
        str(MODEL_OUT), custom_objects=CUSTOM_OBJECTS)


# ═════════════════════════════════════════════════════════════════════════════
# TRAINING
# ═════════════════════════════════════════════════════════════════════════════

def train_model(
    X_train, y_train, X_val, y_val, X_test, y_test,
    label_map,
    epochs: int     = 200,
    batch_size: int = 16,
):
    """
    Training WL-BISINDO v3.

    Key settings untuk dataset kecil (~960 train):
      - batch_size=16 (dataset kecil → batch besar = underfitting)
      - Cosine LR decay (1e-3 → 1e-6)
      - Online augmentation (setiap epoch berbeda)
      - EarlyStopping patience=40
      - clipnorm=1.0 (cegah NaN)
    """
    import tensorflow as tf

    num_classes = label_map["num_classes"]
    print(f"\n{'═'*55}")
    print(f"  🧠  Training WL-BISINDO v3 — {num_classes} kelas")
    print(f"{'═'*55}")
    print(f"  Train : {len(X_train)} seq  ({len(set(y_train))} kelas aktif)")
    print(f"  Val   : {len(X_val)} seq")
    print(f"  Test  : {len(X_test)} seq  (unseen signer)")

    # ── Temporal derivatives: 98 → 294 ────────────────────────────────────────
    print(f"\n  📐  Temporal derivatives: {FEATURE_DIM} → {FEATURE_DIM*3}")
    X_tr = add_temporal_derivatives(X_train)
    X_v  = add_temporal_derivatives(X_val)
    X_te = add_temporal_derivatives(X_test)
    input_dim = X_tr.shape[-1]   # 294
    print(f"  Input shape: ({SEQUENCE_LEN}, {input_dim})")

    # ── NaN guard ──────────────────────────────────────────────────────────────
    for name, arr in [("train", X_tr), ("val", X_v), ("test", X_te)]:
        n_bad = np.sum(~np.isfinite(arr))
        if n_bad > 0:
            print(f"  ⚠️  {name}: {n_bad} NaN/inf → 0")
            arr[~np.isfinite(arr)] = 0.0

    # ── Data stats ─────────────────────────────────────────────────────────────
    print(f"\n  📊  Data stats (train):")
    print(f"      mean={X_tr.mean():.4f}  std={X_tr.std():.4f}")
    print(f"      min={X_tr.min():.4f}  max={X_tr.max():.4f}")
    print(f"      zero_frac={((X_tr == 0).sum() / X_tr.size):.2%}")

    # ── One-hot ────────────────────────────────────────────────────────────────
    y_tr_oh = tf.keras.utils.to_categorical(y_train, num_classes)
    y_v_oh  = tf.keras.utils.to_categorical(y_val,   num_classes)

    # ── Build model ────────────────────────────────────────────────────────────
    model = build_model(num_classes=num_classes, input_dim=input_dim)

    steps_per_epoch = max(1, len(X_tr) // batch_size)
    total_steps     = steps_per_epoch * epochs

    lr_schedule = tf.keras.optimizers.schedules.CosineDecay(
        initial_learning_rate=1e-3,
        decay_steps=total_steps,
        alpha=1e-6,
    )

    optimizer = tf.keras.optimizers.Adam(
        learning_rate=lr_schedule,
        clipnorm=1.0,
    )

    model.compile(
        optimizer=optimizer,
        # Label smoothing 0.1 — dari kompetisi, cegah overconfident predictions
        loss=tf.keras.losses.CategoricalCrossentropy(label_smoothing=0.1),
        metrics=['accuracy'],
    )
    model.summary()

    # ── Callbacks ──────────────────────────────────────────────────────────────
    callbacks = [
        tf.keras.callbacks.ModelCheckpoint(
            str(MODEL_OUT), monitor='val_accuracy',
            save_best_only=True, verbose=0),
        tf.keras.callbacks.TerminateOnNaN(),
    ]

    # ── Training loop (manual augmentation per epoch) ─────────────────────────
    print(f"\n🚀  Training {epochs} epoch  (batch={batch_size})\n")
    print(f"  Augmentasi: noise + time_mask + flip + temporal_stretch(±30%) + scale + translate + crop")
    print(f"  Label smoothing: 0.1\n")

    best_val_acc = 0.0
    no_improve   = 0
    history      = {"loss":[], "acc":[], "val_loss":[], "val_acc":[]}

    for epoch in range(epochs):
        # Noise std: mulai agresif (0.02) lalu turun ke 0.01 setelah epoch 50
        # Curriculum: di awal epoch, augmentasi lebih kuat untuk regularisasi
        noise_std = 0.02 if epoch < 50 else 0.01
        X_aug = augment_batch(X_tr, noise_std=noise_std)

        # Shuffle
        perm  = np.random.permutation(len(X_aug))
        X_aug = X_aug[perm]
        y_aug = y_tr_oh[perm]

        h = model.fit(
            X_aug, y_aug,
            validation_data=(X_v, y_v_oh),
            epochs=1,
            batch_size=batch_size,
            verbose=0,
            callbacks=callbacks,
        )

        tr_loss = h.history['loss'][0]
        tr_acc  = h.history['accuracy'][0]
        v_loss  = h.history['val_loss'][0]
        v_acc   = h.history['val_accuracy'][0]

        history["loss"].append(tr_loss)
        history["acc"].append(tr_acc)
        history["val_loss"].append(v_loss)
        history["val_acc"].append(v_acc)

        # NaN guard
        if not np.isfinite(tr_loss):
            print(f"  ❌  NaN di epoch {epoch+1}!")
            break

        # Print progress
        if (epoch+1) % 10 == 0 or epoch == 0:
            lr_now = float(lr_schedule(epoch * steps_per_epoch))
            print(f"  Epoch {epoch+1:3d}/{epochs}  "
                  f"loss={tr_loss:.4f}  acc={tr_acc:.4f}  "
                  f"val_loss={v_loss:.4f}  val_acc={v_acc:.4f}  "
                  f"lr={lr_now:.2e}")

        # Early stopping
        if v_acc > best_val_acc:
            best_val_acc = v_acc
            no_improve   = 0
        else:
            no_improve += 1

        if no_improve >= 40:
            print(f"\n  ⏹  Early stopping epoch {epoch+1}")
            print(f"     Best val_acc: {best_val_acc:.4f}")
            break

    # ── Evaluasi Test Set ──────────────────────────────────────────────────────
    print(f"\n{'═'*55}")
    print(f"  📊  Test Set — Unseen Signer")
    print(f"{'═'*55}")

    if MODEL_OUT.exists():
        try:
            model = _load_best_model()
            print("  ✅  Loaded best checkpoint")
        except Exception as e:
            print(f"  ⚠️  Tidak bisa load checkpoint ({e}), pakai model terakhir")

    y_pred   = np.argmax(model.predict(X_te, verbose=0), axis=1)
    test_acc = (y_pred == y_test).mean()

    print(f"\n  Test Accuracy: {test_acc:.4f} ({test_acc*100:.1f}%)")
    print(f"  Best Val Acc : {best_val_acc:.4f} ({best_val_acc*100:.1f}%)")

    i2l = label_map["index_to_label"]
    print(f"\n  Per-kelas:")
    for idx in sorted(set(y_test)):
        mask  = y_test == idx
        n     = mask.sum()
        acc_k = (y_pred[mask] == idx).mean()
        bar   = "█" * int(acc_k * 20)
        label = i2l.get(str(idx), str(idx))
        print(f"    [{idx:2d}] {label:<15} {n:>3} seq  {acc_k:.2f}  {bar}")

    # Confusion matrix — top errors
    print(f"\n  Top 5 confusions:")
    from collections import Counter
    errors = []
    for true_i, pred_i in zip(y_test, y_pred):
        if true_i != pred_i:
            errors.append((i2l[str(true_i)], i2l[str(pred_i)]))
    for (t, p), count in Counter(errors).most_common(5):
        print(f"    {t} → {p}  ({count}×)")

    model.save(str(MODEL_OUT))
    print(f"\n✅  Model → {MODEL_OUT}")
    return model, history


# ═════════════════════════════════════════════════════════════════════════════
# TFLITE CONVERSION
# ═════════════════════════════════════════════════════════════════════════════

def convert_to_tflite(model=None, X_repr=None):
    """
    Konversi ke TFLite dengan int8 quantization.
    Output: float32 input → int8 weights → float32 output
    """
    import tensorflow as tf

    if model is None:
        model = tf.keras.models.load_model(str(MODEL_OUT))

    converter = tf.lite.TFLiteConverter.from_keras_model(model)

    if X_repr is not None:
        # Pastikan sudah berupa derivatives (294-dim)
        if X_repr.shape[-1] == FEATURE_DIM:
            X_repr = add_temporal_derivatives(X_repr)
        X_repr = np.nan_to_num(X_repr, nan=0.0)

        def rep_gen():
            for i in range(min(200, len(X_repr))):
                yield [X_repr[i:i+1].astype(np.float32)]

        converter.optimizations          = [tf.lite.Optimize.DEFAULT]
        converter.representative_dataset = rep_gen
        converter.target_spec.supported_ops = [
            tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
        converter.inference_input_type  = tf.float32
        converter.inference_output_type = tf.float32
        print("  Mode: int8 quantization (float32 I/O)")
    else:
        converter.optimizations = [tf.lite.Optimize.DEFAULT]
        print("  Mode: default optimization")

    tflite_model = converter.convert()
    with open(TFLITE_OUT, "wb") as f:
        f.write(tflite_model)

    sz = len(tflite_model) / 1024 / 1024
    print(f"\n✅  TFLite → {TFLITE_OUT}  ({sz:.2f} MB)")
    print(f"\n  📱  Deploy ke Flutter:")
    print(f"     1. Copy ke assets/models/bisindo_wl_model.tflite")
    print(f"     2. Copy ke assets/models/bisindo_wl_labels.json")
    print(f"     3. Update mediapipe_service.dart → 98-dim + std normalization")
    print(f"     4. Update gesture_service.dart   → temporal derivatives (294-dim)")
    print(f"     5. Model input: ({SEQUENCE_LEN}, {FEATURE_DIM*3}) float32")


# ═════════════════════════════════════════════════════════════════════════════
# KAGGLE NOTEBOOK — COPY-PASTE CELLS
# ═════════════════════════════════════════════════════════════════════════════
#
# ┌─────────────────────────────────────────────────────────┐
# │ Cell 0 — Install MediaPipe (sekali, lalu restart kernel)│
# ├─────────────────────────────────────────────────────────┤
# │ !pip install mediapipe==0.9.3.0 -q                      │
# │ print("✅ Restart kernel sekarang!")                     │
# └─────────────────────────────────────────────────────────┘
#
# ┌─────────────────────────────────────────────────────────┐
# │ Cell 1 — Sanity check                                   │
# ├─────────────────────────────────────────────────────────┤
# │ # Paste seluruh isi file ini ke satu cell               │
# │ # Atau upload lalu:                                      │
# │ # from kaggle_bisindo_wl import *                        │
# │ sanity_check()                                           │
# └─────────────────────────────────────────────────────────┘
#
# ┌─────────────────────────────────────────────────────────┐
# │ Cell 2 — Extract MediaPipe features (± 15 menit)        │
# ├─────────────────────────────────────────────────────────┤
# │ stats = run_pipeline()                                   │
# └─────────────────────────────────────────────────────────┘
#
# ┌─────────────────────────────────────────────────────────┐
# │ Cell 3 — Load dataset (LOSO split)                       │
# ├─────────────────────────────────────────────────────────┤
# │ X_tr,y_tr, X_v,y_v, X_te,y_te, lm = \                  │
# │     load_dataset_for_training()                          │
# └─────────────────────────────────────────────────────────┘
#
# ┌─────────────────────────────────────────────────────────┐
# │ Cell 4 — Training (± 10 menit GPU)                       │
# ├─────────────────────────────────────────────────────────┤
# │ model, hist = train_model(                               │
# │     X_tr, y_tr, X_v, y_v, X_te, y_te, lm,              │
# │     epochs=200, batch_size=16)                           │
# └─────────────────────────────────────────────────────────┘
#
# ┌─────────────────────────────────────────────────────────┐
# │ Cell 5 — TFLite untuk Android                           │
# ├─────────────────────────────────────────────────────────┤
# │ convert_to_tflite(model, X_repr=X_tr[:100])             │
# └─────────────────────────────────────────────────────────┘
# ═════════════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    sanity_check()
