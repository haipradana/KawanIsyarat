#!/usr/bin/env python3
"""
data_collector.py — KawanIsyarat SLR Dataset Collector
=======================================================
Mengumpulkan data gesture BISINDO untuk training model.

Feature vector: 94 floats per frame (RAW positions — derivatives dihitung saat training)
  [0:42]   = Tangan KANAN: 21 × (x,y), nose-centered + shoulder-normalized
  [42:84]  = Tangan KIRI:  21 × (x,y), nose-centered + shoulder-normalized
  [84:94]  = Pose anchor:  5 titik × (x,y)
               [84:86] = nose
               [86:88] = left shoulder
               [88:90] = right shoulder
               [90:92] = left ear
               [92:94] = right ear

Normalisasi (Boháček-style, mengikuti 1st place Kaggle ASL Signs):
  - Semua koordinat digeser relatif ke hidung (nose-centered)
  - Semua dibagi shoulder_width (scale-invariant terhadap jarak kamera)
  - Zero-padding jika tangan/pose tidak terdeteksi

Saat TRAINING (bukan di sini), tambahkan temporal derivatives:
  velocity     = x[t] - x[t-1]    → 94 floats
  acceleration = x[t] - x[t-2]    → 94 floats
  Total input ke model: 94 × 3 = 282 floats/frame

Target BISINDO vocabulary (fase 1):
  TULI, SAYA, KAMU, NAMA, TOLONG, APA, TERIMA_KASIH,
  BAIK, SAKIT, LAPAR, HAUS, MINTA, PAGI, MALAM, SEKOLAH,
  NOISE  ← wajib direkam ~60 sequences

Modes:
  webcam  LABEL -n N   rekam dari webcam (default: 50 sequences)
  video   FILE  LABEL  ekstrak dari satu file video
  videos  FOLDER LABEL ekstrak semua video dalam folder
  stats               tampilkan ringkasan dataset

Usage:
  python data_collector.py webcam TULI
  python data_collector.py webcam NOISE -n 60
  python data_collector.py videos ./raw/saya/ SAYA
  python data_collector.py stats
"""

import argparse
import cv2
import mediapipe as mp
import numpy as np
from pathlib import Path

# ── MediaPipe ─────────────────────────────────────────────────────────────────
mp_hands  = mp.solutions.hands
mp_pose   = mp.solutions.pose
mp_draw   = mp.solutions.drawing_utils
mp_styles = mp.solutions.drawing_styles

# ── Constants ─────────────────────────────────────────────────────────────────
SEQUENCE_LEN = 30       # frames per sequence
FEATURE_DIM  = 94       # floats per frame (raw, tanpa derivatives)
SAVE_DIR     = "dataset"
TARGET_FPS   = 15       # 30 frame ÷ 15fps = 2 detik per sequence
MS_PER_FRAME = int(1000 / TARGET_FPS)

# MediaPipe Pose landmark indices yang kita pakai
POSE_NOSE       = 0
POSE_L_EAR      = 7
POSE_R_EAR      = 8
POSE_L_SHOULDER = 11
POSE_R_SHOULDER = 12

# 5 pose anchors yang disimpan (urutan = layout di feature vector)
POSE_ANCHOR_IDX = [POSE_NOSE, POSE_L_SHOULDER, POSE_R_SHOULDER,
                   POSE_L_EAR, POSE_R_EAR]

# Vocabulary target BISINDO fase 1
BISINDO_LABELS = [
    "TULI", "SAYA", "KAMU", "NAMA", "TOLONG",
    "APA", "TERIMA_KASIH", "BAIK", "SAKIT", "LAPAR",
    "HAUS", "MINTA", "PAGI", "MALAM", "SEKOLAH",
    "NOISE",
]


# ─────────────────────────────────────────────────────────────────────────────
# Feature extraction
# ─────────────────────────────────────────────────────────────────────────────

def extract_features(hand_result, pose_result) -> np.ndarray:
    """
    Bangun 94-float feature vector dari satu frame MediaPipe result.

    Normalisasi nose-centered + shoulder-width scaling:
      semua (x,y) = (raw - nose_pos) / shoulder_width

    Layout output:
      [0:42]  = right hand 21 × (x,y)
      [42:84] = left hand  21 × (x,y)
      [84:94] = pose anchors 5 × (x,y): nose, l_sho, r_sho, l_ear, r_ear

    Jika tangan atau pose tidak terdeteksi → zero-padding untuk bagian itu.
    Pose anchor tetap dicoba ekstrak bahkan jika tangan tidak ada.
    """
    out = np.zeros(FEATURE_DIM, dtype=np.float32)

    # ── Pose anchors ──────────────────────────────────────────────────────────
    nose_x, nose_y   = 0.5, 0.5   # default center jika pose tidak detect
    shoulder_w       = 0.3        # default width
    has_pose         = False

    if pose_result.pose_landmarks:
        lm         = pose_result.pose_landmarks.landmark
        nose_x     = lm[POSE_NOSE].x
        nose_y     = lm[POSE_NOSE].y
        lsx, lsy   = lm[POSE_L_SHOULDER].x, lm[POSE_L_SHOULDER].y
        rsx, rsy   = lm[POSE_R_SHOULDER].x, lm[POSE_R_SHOULDER].y
        shoulder_w = max(abs(rsx - lsx), 1e-6)
        has_pose   = True

        # Simpan 5 anchor (nose-centered, shoulder-normalized)
        for i, idx in enumerate(POSE_ANCHOR_IDX):
            out[84 + i*2]     = (lm[idx].x - nose_x) / shoulder_w
            out[84 + i*2 + 1] = (lm[idx].y - nose_y) / shoulder_w

    # ── Hand landmarks ────────────────────────────────────────────────────────
    if hand_result.multi_hand_landmarks is None:
        return out

    for i, hand_lm in enumerate(hand_result.multi_hand_landmarks):
        # Tentukan kiri/kanan
        if hand_result.multi_handedness and i < len(hand_result.multi_handedness):
            label    = hand_result.multi_handedness[i].classification[0].label
            is_right = (label == "Right")
        else:
            is_right = (i == 0)

        base = 0 if is_right else 42  # right=0..41, left=42..83

        for j, lm in enumerate(hand_lm.landmark):
            # Nose-centered + shoulder-normalized
            out[base + j*2]     = (lm.x - nose_x) / shoulder_w
            out[base + j*2 + 1] = (lm.y - nose_y) / shoulder_w

    return out


def process_frame(frame: np.ndarray, hands, pose) -> tuple:
    """BGR frame → (feature_94, annotated_frame)."""
    rgb      = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    h_result = hands.process(rgb)
    p_result = pose.process(rgb)
    features = extract_features(h_result, p_result)

    # Annotate: hand skeleton
    if h_result.multi_hand_landmarks:
        for lm in h_result.multi_hand_landmarks:
            mp_draw.draw_landmarks(
                frame, lm, mp_hands.HAND_CONNECTIONS,
                mp_styles.get_default_hand_landmarks_style(),
                mp_styles.get_default_hand_connections_style(),
            )

    return features, frame


# ─────────────────────────────────────────────────────────────────────────────
# Mode 1: Webcam
# ─────────────────────────────────────────────────────────────────────────────

def collect_from_webcam(label: str, num_sequences: int = 50):
    save_path = Path(SAVE_DIR) / label
    save_path.mkdir(parents=True, exist_ok=True)

    existing     = len(list(save_path.glob("seq_*.npy")))
    target       = existing + num_sequences
    duration_sec = SEQUENCE_LEN / TARGET_FPS

    print(f"\n{'─'*55}")
    print(f"  🎯  Label    : {label}")
    print(f"  📂  Save dir : {save_path}")
    print(f"  📊  Progress : {existing} ada, +{num_sequences} → total {target}")
    print(f"  ⏱️   Durasi   : {duration_sec:.1f} detik per sequence ({SEQUENCE_LEN} frame @ {TARGET_FPS}fps)")
    if label == "NOISE":
        print(f"  ℹ️   NOISE: gerakkan tangan sembarangan, diam, garuk kepala, transisi")
    print(f"{'─'*55}")
    print(f"\n  SPACE = mulai rekam  |  R = ulangi sequence terakhir  |  Q = keluar\n")

    cap     = cv2.VideoCapture(0)
    seq_idx = existing
    last_was_bad = False  # flag untuk ulangi

    with mp_hands.Hands(max_num_hands=2,
                        min_detection_confidence=0.6,
                        min_tracking_confidence=0.5) as hands, \
         mp_pose.Pose(min_detection_confidence=0.5,
                      min_tracking_confidence=0.5) as pose:

        while seq_idx < target:

            # ── Preview — tunggu SPACE ─────────────────────────────────────
            while True:
                ret, frame = cap.read()
                if not ret:
                    break
                frame       = cv2.flip(frame, 1)
                feats, frame = process_frame(frame.copy(), hands, pose)

                # Indikator tangan terdeteksi
                has_hands = np.any(feats[:84] != 0)
                dot_color = (0, 220, 80) if has_hands else (60, 60, 60)
                cv2.circle(frame, (frame.shape[1]-20, 20), 8, dot_color, -1)

                _bar(frame, f"[{label}] {seq_idx}/{target}  |  SPACE=rekam  Q=keluar",
                     (0, 180, 80))
                cv2.imshow("KawanIsyarat Collector", frame)

                key = cv2.waitKey(1) & 0xFF
                if key == ord('q'):
                    cap.release()
                    cv2.destroyAllWindows()
                    _summary(label, seq_idx - existing)
                    return
                if key == ord(' '):
                    break

            # ── Countdown ─────────────────────────────────────────────────
            for n in [3, 2, 1]:
                ret, frame = cap.read()
                frame = cv2.flip(frame, 1)
                h, w  = frame.shape[:2]
                cv2.putText(frame, str(n), (w//2 - 35, h//2 + 30),
                            cv2.FONT_HERSHEY_SIMPLEX, 5, (0, 255, 0), 8)
                cv2.imshow("KawanIsyarat Collector", frame)
                cv2.waitKey(700)

            # ── Rekam ──────────────────────────────────────────────────────
            sequence    = []
            hand_frames = 0

            for fi in range(SEQUENCE_LEN):
                ret, frame = cap.read()
                if not ret:
                    sequence.append(np.zeros(FEATURE_DIM, dtype=np.float32))
                    continue
                frame        = cv2.flip(frame, 1)
                feats, frame = process_frame(frame.copy(), hands, pose)
                sequence.append(feats)

                if np.any(feats[:84] != 0):
                    hand_frames += 1

                # Progress bar bawah
                prog = int((fi / SEQUENCE_LEN) * frame.shape[1])
                cv2.rectangle(frame,
                              (0, frame.shape[0]-8),
                              (prog, frame.shape[0]),
                              (0, 180, 255), -1)
                _bar(frame,
                     f"● REC [{label}] #{seq_idx+1}  "
                     f"frame {fi+1}/{SEQUENCE_LEN}  hands={hand_frames}",
                     (0, 0, 200))
                cv2.imshow("KawanIsyarat Collector", frame)
                cv2.waitKey(MS_PER_FRAME)

            # ── Simpan / warning ───────────────────────────────────────────
            arr = np.array(sequence, dtype=np.float32)  # (30, 94)

            if hand_frames < 5 and label != "NOISE":
                print(f"  ⚠  Sequence #{seq_idx+1} DIBUANG — tangan hanya "
                      f"terdeteksi {hand_frames}/30 frame. Ulangi!")
                # Tampilkan warning di preview sebentar
                ret, frame = cap.read()
                frame = cv2.flip(frame, 1) if ret else np.zeros((480,640,3), np.uint8)
                _bar(frame, "⚠  TANGAN KURANG TERDETEKSI — ulangi (SPACE)", (0, 60, 220))
                cv2.imshow("KawanIsyarat Collector", frame)
                cv2.waitKey(1500)
                continue   # jangan increment seq_idx

            out_path = save_path / f"seq_{seq_idx:04d}.npy"
            np.save(out_path, arr)
            print(f"  ✓  seq_{seq_idx:04d}.npy  "
                  f"hands={hand_frames}/{SEQUENCE_LEN} frames  "
                  f"shape={arr.shape}")
            seq_idx += 1

    cap.release()
    cv2.destroyAllWindows()
    _summary(label, seq_idx - existing)


# ─────────────────────────────────────────────────────────────────────────────
# Mode 2 & 3: Dari video
# ─────────────────────────────────────────────────────────────────────────────

def extract_from_video(video_path: str, label: str) -> np.ndarray:
    """Satu video → (SEQUENCE_LEN, FEATURE_DIM) array."""
    cap   = cv2.VideoCapture(video_path)
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

    if total <= 0:
        print(f"  ✗  Tidak bisa baca: {video_path}")
        cap.release()
        return np.zeros((SEQUENCE_LEN, FEATURE_DIM), dtype=np.float32)

    indices = np.linspace(0, total - 1, SEQUENCE_LEN, dtype=int)
    seq     = []

    with mp_hands.Hands(max_num_hands=2, min_detection_confidence=0.5) as hands, \
         mp_pose.Pose(min_detection_confidence=0.4) as pose:

        for fi in indices:
            cap.set(cv2.CAP_PROP_POS_FRAMES, int(fi))
            ret, frame = cap.read()
            if not ret:
                seq.append(np.zeros(FEATURE_DIM, dtype=np.float32))
                continue
            feats, _ = process_frame(frame, hands, pose)
            seq.append(feats)

    cap.release()

    while len(seq) < SEQUENCE_LEN:
        seq.append(np.zeros(FEATURE_DIM, dtype=np.float32))

    save_path = Path(SAVE_DIR) / label
    save_path.mkdir(parents=True, exist_ok=True)
    existing = len(list(save_path.glob("seq_*.npy")))

    arr      = np.array(seq[:SEQUENCE_LEN], dtype=np.float32)
    out_path = save_path / f"seq_{existing:04d}.npy"
    np.save(out_path, arr)

    hands_detected = np.any(arr[:, :84] != 0, axis=1).sum()
    print(f"  ✓  {Path(video_path).name}  →  {out_path}  "
          f"hands={hands_detected}/{SEQUENCE_LEN}")
    return arr


def extract_from_video_folder(folder: str, label: str):
    """Semua video dalam folder → sequences untuk satu label."""
    folder = Path(folder)
    exts   = {".mp4", ".avi", ".mov", ".mkv", ".webm"}
    videos = sorted(f for f in folder.iterdir() if f.suffix.lower() in exts)

    print(f"\n📂  {folder}  →  {len(videos)} video  →  label '{label}'")
    for v in videos:
        extract_from_video(str(v), label)
    print(f"\n✅  Selesai '{label}'")


# ─────────────────────────────────────────────────────────────────────────────
# Stats
# ─────────────────────────────────────────────────────────────────────────────

def print_stats():
    root = Path(SAVE_DIR)
    if not root.exists():
        print("Dataset belum ada.")
        return

    print(f"\n{'─'*45}")
    print(f"  📊  Dataset: {SAVE_DIR}/  (FEATURE_DIM={FEATURE_DIM})")
    print(f"{'─'*45}")

    total = 0
    labels_done   = []
    labels_remain = list(BISINDO_LABELS)

    for d in sorted(root.iterdir()):
        if not d.is_dir():
            continue
        n = len(list(d.glob("seq_*.npy")))
        status = "✓" if n >= 40 else ("~" if n >= 20 else "✗")
        print(f"  {status}  {d.name:<20} {n:>4} sequences")
        total += n
        if d.name in labels_remain:
            labels_remain.remove(d.name)
            labels_done.append(d.name)

    print(f"{'─'*45}")
    print(f"     {'TOTAL':<20} {total:>4} sequences")

    if labels_remain:
        print(f"\n  ⏳  Belum direkam ({len(labels_remain)}):")
        for l in labels_remain:
            print(f"     - {l}")

    print(f"\n  Jalankan: python data_collector.py webcam <LABEL>\n")


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def _bar(frame, text: str, color=(0, 200, 80)):
    cv2.rectangle(frame, (0, 0), (frame.shape[1], 46), (0, 0, 0), -1)
    cv2.putText(frame, text, (10, 30),
                cv2.FONT_HERSHEY_SIMPLEX, 0.62, color, 2)


def _summary(label, n_saved):
    print(f"\n✅  Selesai! {n_saved} sequences tersimpan untuk '{label}'")
    print(f"   Jalankan 'python data_collector.py stats' untuk progress.\n")


# ─────────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="KawanIsyarat BISINDO Data Collector",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=f"""
Target vocabulary fase 1 ({len(BISINDO_LABELS)} kelas):
  {', '.join(BISINDO_LABELS)}

Contoh:
  python data_collector.py webcam TULI
  python data_collector.py webcam NOISE -n 60
  python data_collector.py webcam SAYA -n 50
  python data_collector.py videos ./raw/terima_kasih/ TERIMA_KASIH
  python data_collector.py stats
        """
    )

    sub = parser.add_subparsers(dest="mode")

    # webcam
    wp = sub.add_parser("webcam", help="Rekam dari webcam")
    wp.add_argument("label",            help="Nama gesture (dari daftar BISINDO_LABELS)")
    wp.add_argument("-n", "--num",
                    type=int, default=50, help="Jumlah sequences (default: 50)")

    # video satu file
    vp = sub.add_parser("video", help="Ekstrak dari satu file video")
    vp.add_argument("video_path")
    vp.add_argument("label")

    # folder video
    vfp = sub.add_parser("videos", help="Ekstrak semua video dalam folder")
    vfp.add_argument("folder")
    vfp.add_argument("label")

    # stats
    sub.add_parser("stats", help="Tampilkan ringkasan dataset")

    args = parser.parse_args()

    if args.mode == "webcam":
        collect_from_webcam(args.label.upper(), args.num)
    elif args.mode == "video":
        extract_from_video(args.video_path, args.label.upper())
    elif args.mode == "videos":
        extract_from_video_folder(args.folder, args.label.upper())
    elif args.mode == "stats":
        print_stats()
    else:
        parser.print_help()
        print("\n💡  Mulai dari:")
        print("    python data_collector.py webcam TULI")
        print("    python data_collector.py webcam NOISE -n 60")


if __name__ == "__main__":
    main()
