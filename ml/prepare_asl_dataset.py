#!/usr/bin/env python3
"""
prepare_asl_dataset.py — Konversi dataset ASL ke format KawanIsyarat (100 floats)
==================================================================================
Mendukung dua sumber dataset ASL yang tersedia gratis:

1. Google ASL Signs (Kaggle) — REKOMENDASI
   - URL  : https://www.kaggle.com/competitions/asl-signs/data
   - Isi  : 250 kata ASL, landmark sudah di-extract oleh Google ke parquet
   - Size : ~3GB landmark files (tidak perlu download video!)
   - Cara : kaggle competitions download -c asl-signs

2. WLASL (Word-Level ASL) — untuk kata yang tidak ada di Google ASL
   - URL  : https://www.kaggle.com/datasets/sttaseen/wlasl2000-resized
   - Isi  : 2000 kata ASL dalam format video MP4
   - Size : ~3GB video
   - Cara : kaggle datasets download -d sttaseen/wlasl2000-resized

Output: dataset/ASL_<SIGN>/seq_XXXX.npy  shape=(30, 100)
        Format identik dengan data_collector.py → bisa langsung digabung untuk training.

Feature vector: 100 floats (identik dengan data_collector.py)
  [0:42]   = Tangan KANAN shape (bbox-normalized)
  [42:50]  = Tangan KANAN location (wrist+indextip relatif ke shoulder & hidung)
  [50:92]  = Tangan KIRI  shape
  [92:100] = Tangan KIRI  location

Usage:
  # Google ASL Signs (parquet):
  python prepare_asl_dataset.py google --data-dir ./asl-signs --signs hello thank_you yes no

  # Google ASL Signs — semua 250 kata:
  python prepare_asl_dataset.py google --data-dir ./asl-signs --all

  # WLASL (video):
  python prepare_asl_dataset.py wlasl --data-dir ./wlasl2000 --signs hello yes no

  # Lihat daftar kata tersedia di dataset Google:
  python prepare_asl_dataset.py google --data-dir ./asl-signs --list
"""

import argparse
import json
import os
from pathlib import Path

import cv2
import mediapipe as mp
import numpy as np
import pandas as pd

# ── MediaPipe setup ───────────────────────────────────────────────────────────
mp_hands = mp.solutions.hands
mp_pose  = mp.solutions.pose

# ── Constants ─────────────────────────────────────────────────────────────────
SEQUENCE_LEN = 30
FEATURE_DIM  = 100
SAVE_DIR     = "dataset"

# Pose landmark indices
IDX_NOSE       = 0
IDX_L_SHOULDER = 11
IDX_R_SHOULDER = 12

# Hand landmark indices
IDX_WRIST      = 0
IDX_INDEX_TIP  = 8

# Subset kata ASL yang relevan/overlap dengan BISINDO common words
DEFAULT_SIGNS = [
    # Sapaan & dasar
    "hello", "thank_you", "please", "sorry", "yes", "no", "help",
    # Orang & identitas
    "mother", "father", "friend", "name", "deaf", "hearing",
    # Aktivitas dasar
    "eat", "drink", "sleep", "go", "come", "stop", "want", "need",
    # Tempat & navigasi
    "home", "school", "hospital", "bathroom", "where",
    # Waktu
    "today", "tomorrow", "morning", "night",
    # Emosi
    "happy", "sad", "pain", "sick",
    # Angka (pilihan)
    "one", "two", "three", "four", "five",
]


# ─────────────────────────────────────────────────────────────────────────────
# Feature extraction (sama dengan data_collector.py)
# ─────────────────────────────────────────────────────────────────────────────

def normalize_hand_shape(coords_21x2: np.ndarray) -> np.ndarray:
    """Boháček normalization: 21 × (x,y) → 42 floats bbox-normalized."""
    min_x, min_y = coords_21x2[:, 0].min(), coords_21x2[:, 1].min()
    max_x, max_y = coords_21x2[:, 0].max(), coords_21x2[:, 1].max()
    w = max(max_x - min_x, 1e-6)
    h = max(max_y - min_y, 1e-6)
    norm = np.zeros_like(coords_21x2, dtype=np.float32)
    norm[:, 0] = (coords_21x2[:, 0] - min_x) / w
    norm[:, 1] = (coords_21x2[:, 1] - min_y) / h
    return norm.flatten()


def get_location_features_from_arrays(
    hand_xy: np.ndarray,   # (21, 2) — tangan
    nose_xy: np.ndarray,   # (2,)
    l_sho_xy: np.ndarray,  # (2,)
    r_sho_xy: np.ndarray,  # (2,)
) -> np.ndarray:
    """8 floats: wrist + index_tip relatif ke mid-shoulder & hidung."""
    out = np.zeros(8, dtype=np.float32)
    shoulder_w = max(abs(r_sho_xy[0] - l_sho_xy[0]), 1e-6)
    mid_x = (l_sho_xy[0] + r_sho_xy[0]) / 2.0
    mid_y = (l_sho_xy[1] + r_sho_xy[1]) / 2.0

    wrist     = hand_xy[IDX_WRIST]
    index_tip = hand_xy[IDX_INDEX_TIP]

    def rel(pt, rx, ry):
        return np.array([(pt[0] - rx) / shoulder_w,
                         (pt[1] - ry) / shoulder_w], dtype=np.float32)

    out[0:2] = rel(wrist,     mid_x,    mid_y)
    out[2:4] = rel(wrist,     nose_xy[0], nose_xy[1])
    out[4:6] = rel(index_tip, mid_x,    mid_y)
    out[6:8] = rel(index_tip, nose_xy[0], nose_xy[1])
    return out


# ─────────────────────────────────────────────────────────────────────────────
# Source 1: Google ASL Signs (Kaggle parquet)
# ─────────────────────────────────────────────────────────────────────────────
# Dataset sudah berisi landmark MediaPipe — tidak perlu jalankan MediaPipe lagi.
# Struktur:
#   asl-signs/
#     train.csv                          ← sequence_id, path, sign
#     train_landmark_files/
#       <participant_id>/<sequence_id>.parquet
#
# Setiap parquet: frame | type | landmark_index | x | y | z
#   type: 'face' | 'left_hand' | 'right_hand' | 'pose'

def _load_parquet_sequence(parquet_path: str) -> np.ndarray:
    """
    Load satu parquet → (SEQUENCE_LEN, 100) float32.
    Subsample uniform ke SEQUENCE_LEN frame.
    """
    df = pd.read_parquet(parquet_path)
    frames = sorted(df['frame'].unique())
    n = len(frames)

    if n == 0:
        return np.zeros((SEQUENCE_LEN, FEATURE_DIM), dtype=np.float32)

    # Subsample uniform → SEQUENCE_LEN frame
    if n >= SEQUENCE_LEN:
        indices = np.linspace(0, n - 1, SEQUENCE_LEN, dtype=int)
        sel_frames = [frames[i] for i in indices]
    else:
        sel_frames = frames  # nanti di-pad

    sequence = []
    for fid in sel_frames:
        fdf = df[df['frame'] == fid]
        feat = _extract_features_from_frame_df(fdf)
        sequence.append(feat)

    # Zero-pad jika kurang dari SEQUENCE_LEN
    while len(sequence) < SEQUENCE_LEN:
        sequence.append(np.zeros(FEATURE_DIM, dtype=np.float32))

    return np.array(sequence[:SEQUENCE_LEN], dtype=np.float32)


def _extract_features_from_frame_df(fdf: pd.DataFrame) -> np.ndarray:
    """Bangun 100-float feature vector dari satu frame parquet."""
    features = np.zeros(FEATURE_DIM, dtype=np.float32)

    def get_landmarks(ltype, n_lm):
        sub = fdf[fdf['type'] == ltype].sort_values('landmark_index')
        if len(sub) < n_lm:
            return None
        return sub[['x', 'y']].values[:n_lm].astype(np.float32)  # (n_lm, 2)

    right_hand = get_landmarks('right_hand', 21)
    left_hand  = get_landmarks('left_hand',  21)
    pose       = get_landmarks('pose',       33)

    # Pose anchors
    if pose is not None and len(pose) > IDX_R_SHOULDER:
        nose_xy  = pose[IDX_NOSE]
        l_sho_xy = pose[IDX_L_SHOULDER]
        r_sho_xy = pose[IDX_R_SHOULDER]
        has_pose = True
    else:
        nose_xy = l_sho_xy = r_sho_xy = np.array([0.5, 0.5], dtype=np.float32)
        has_pose = False

    if right_hand is not None:
        features[0:42]  = normalize_hand_shape(right_hand)
        if has_pose:
            features[42:50] = get_location_features_from_arrays(
                right_hand, nose_xy, l_sho_xy, r_sho_xy)

    if left_hand is not None:
        features[50:92]  = normalize_hand_shape(left_hand)
        if has_pose:
            features[92:100] = get_location_features_from_arrays(
                left_hand, nose_xy, l_sho_xy, r_sho_xy)

    return features


def process_google_asl(data_dir: str, signs: list[str], max_per_sign: int = 200):
    """
    Proses dataset Google ASL Signs (Kaggle parquet format).
    signs: list nama gesture (misal ['hello', 'yes', 'no'])
    """
    data_dir = Path(data_dir)
    train_csv = data_dir / "train.csv"

    if not train_csv.exists():
        print(f"✗  train.csv tidak ditemukan di {data_dir}")
        print(f"   Download dulu: kaggle competitions download -c asl-signs")
        return

    df = pd.read_csv(train_csv)
    available = sorted(df['sign'].unique())

    # Validasi signs
    missing = [s for s in signs if s not in available]
    if missing:
        print(f"⚠  Tidak ditemukan di dataset: {missing}")
        print(f"   Gunakan --list untuk melihat semua kata tersedia.")
    signs = [s for s in signs if s in available]

    print(f"\n🔄  Memproses {len(signs)} kata dari Google ASL Signs...")

    for sign in signs:
        rows = df[df['sign'] == sign].head(max_per_sign)
        save_path = Path(SAVE_DIR) / f"ASL_{sign.upper()}"
        save_path.mkdir(parents=True, exist_ok=True)
        existing = len(list(save_path.glob("seq_*.npy")))

        print(f"\n  [{sign}]  {len(rows)} sequences tersedia")
        saved = 0

        for _, row in rows.iterrows():
            parquet_path = data_dir / row['path']
            if not parquet_path.exists():
                continue

            seq = _load_parquet_sequence(str(parquet_path))
            hands_detected = np.any(seq != 0, axis=1).sum()

            if hands_detected < 5:
                continue  # skip jika hampir semua frame kosong

            out_path = save_path / f"seq_{existing + saved:04d}.npy"
            np.save(out_path, seq)
            saved += 1

        print(f"  ✓  {saved} sequences tersimpan → {save_path}")

    print(f"\n✅  Selesai proses Google ASL Signs.")


def list_google_asl_signs(data_dir: str):
    """Tampilkan semua kata yang tersedia di dataset Google ASL."""
    train_csv = Path(data_dir) / "train.csv"
    if not train_csv.exists():
        print(f"train.csv tidak ditemukan di {data_dir}")
        return
    df    = pd.read_csv(train_csv)
    signs = sorted(df['sign'].unique())
    counts = df['sign'].value_counts()
    print(f"\n📋  {len(signs)} kata tersedia di Google ASL Signs:\n")
    for i, s in enumerate(signs):
        print(f"  {s:<25} ({counts[s]:>3} sequences)", end="\n" if (i+1) % 3 == 0 else "  ")
    print()


# ─────────────────────────────────────────────────────────────────────────────
# Source 2: WLASL (video MP4)
# ─────────────────────────────────────────────────────────────────────────────
# Struktur WLASL setelah extract:
#   wlasl2000/
#     WLASL_v0.3.json     ← metadata
#     videos/
#       <gloss>/
#         <video_id>.mp4

def process_wlasl(data_dir: str, signs: list[str], max_per_sign: int = 50):
    """
    Proses dataset WLASL (video MP4 format).
    Jalankan MediaPipe pada setiap video → ekstrak fitur.
    """
    data_dir   = Path(data_dir)
    json_path  = data_dir / "WLASL_v0.3.json"
    videos_dir = data_dir / "videos"

    if not json_path.exists():
        # Coba struktur flat (folder per gloss langsung)
        if videos_dir.exists():
            print("  WLASL_v0.3.json tidak ditemukan, coba struktur folder langsung...")
            _process_wlasl_folders(videos_dir, signs, max_per_sign)
            return
        print(f"✗  WLASL_v0.3.json tidak ditemukan di {data_dir}")
        print(f"   Download: kaggle datasets download -d sttaseen/wlasl2000-resized")
        return

    with open(json_path) as f:
        data = json.load(f)

    # Build index: gloss → list of video paths
    gloss_index = {}
    for entry in data:
        gloss = entry['gloss'].lower().replace(' ', '_')
        if gloss not in gloss_index:
            gloss_index[gloss] = []
        for inst in entry.get('instances', []):
            vid_id = inst.get('video_id', '')
            # Coba beberapa kemungkinan path
            for ext in ['.mp4', '.webm', '.avi']:
                p = videos_dir / f"{vid_id}{ext}"
                if p.exists():
                    gloss_index[gloss].append(str(p))
                    break

    # Validasi
    missing = [s for s in signs if s not in gloss_index]
    if missing:
        print(f"⚠  Tidak ditemukan di WLASL: {missing}")
    signs = [s for s in signs if s in gloss_index]

    print(f"\n🔄  Memproses {len(signs)} kata dari WLASL (video)...")

    with mp_hands.Hands(max_num_hands=2, min_detection_confidence=0.5) as hands, \
         mp_pose.Pose(min_detection_confidence=0.4) as pose:

        for sign in signs:
            videos = gloss_index[sign][:max_per_sign]
            save_path = Path(SAVE_DIR) / f"ASL_{sign.upper()}"
            save_path.mkdir(parents=True, exist_ok=True)
            existing = len(list(save_path.glob("seq_*.npy")))

            print(f"\n  [{sign}]  {len(videos)} video")
            saved = 0

            for vid_path in videos:
                seq = _extract_video_sequence(vid_path, hands, pose)
                hands_detected = np.any(seq != 0, axis=1).sum()

                if hands_detected < 5:
                    continue

                out_path = save_path / f"seq_{existing + saved:04d}.npy"
                np.save(out_path, seq)
                saved += 1
                print(f"    ✓  {Path(vid_path).name}  "
                      f"hands={hands_detected}/{SEQUENCE_LEN}")

            print(f"  → {saved} sequences tersimpan untuk '{sign}'")

    print(f"\n✅  Selesai proses WLASL.")


def _process_wlasl_folders(videos_dir: Path, signs: list[str], max_per_sign: int):
    """Fallback: proses folder flat (videos/HELLO/*.mp4)."""
    with mp_hands.Hands(max_num_hands=2, min_detection_confidence=0.5) as hands, \
         mp_pose.Pose(min_detection_confidence=0.4) as pose:

        for sign in signs:
            folder = videos_dir / sign.lower()
            if not folder.exists():
                folder = videos_dir / sign.upper()
            if not folder.exists():
                print(f"  ⚠  Folder tidak ditemukan: {sign}")
                continue

            exts  = {'.mp4', '.avi', '.mov', '.webm'}
            vids  = sorted(f for f in folder.iterdir()
                           if f.suffix.lower() in exts)[:max_per_sign]
            save_path = Path(SAVE_DIR) / f"ASL_{sign.upper()}"
            save_path.mkdir(parents=True, exist_ok=True)
            existing = len(list(save_path.glob("seq_*.npy")))

            print(f"\n  [{sign}]  {len(vids)} video")
            saved = 0

            for vid in vids:
                seq = _extract_video_sequence(str(vid), hands, pose)
                if np.any(seq != 0, axis=1).sum() < 5:
                    continue
                out_path = save_path / f"seq_{existing + saved:04d}.npy"
                np.save(out_path, seq)
                saved += 1

            print(f"  ✓  {saved} sequences tersimpan")


def _extract_video_sequence(video_path: str, hands, pose) -> np.ndarray:
    """Satu video MP4 → (SEQUENCE_LEN, 100) float32."""
    cap   = cv2.VideoCapture(video_path)
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
            seq.append(np.zeros(FEATURE_DIM, dtype=np.float32))
            continue

        rgb      = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        h_result = hands.process(rgb)
        p_result = pose.process(rgb)

        # Build feature vector dari MediaPipe live results
        features = np.zeros(FEATURE_DIM, dtype=np.float32)
        if h_result.multi_hand_landmarks:
            for i, hand_lm in enumerate(h_result.multi_hand_landmarks):
                if h_result.multi_handedness and i < len(h_result.multi_handedness):
                    label    = h_result.multi_handedness[i].classification[0].label
                    is_right = (label == 'Right')
                else:
                    is_right = (i == 0)

                coords = np.array([[lm.x, lm.y] for lm in hand_lm.landmark],
                                  dtype=np.float32)
                shape  = normalize_hand_shape(coords)

                loc = np.zeros(8, dtype=np.float32)
                if p_result.pose_landmarks:
                    plm      = p_result.pose_landmarks.landmark
                    nose_xy  = np.array([plm[IDX_NOSE].x,       plm[IDX_NOSE].y])
                    l_sho_xy = np.array([plm[IDX_L_SHOULDER].x, plm[IDX_L_SHOULDER].y])
                    r_sho_xy = np.array([plm[IDX_R_SHOULDER].x, plm[IDX_R_SHOULDER].y])
                    loc      = get_location_features_from_arrays(
                        coords, nose_xy, l_sho_xy, r_sho_xy)

                if is_right:
                    features[0:42]  = shape
                    features[42:50] = loc
                else:
                    features[50:92]  = shape
                    features[92:100] = loc

        seq.append(features)

    cap.release()
    while len(seq) < SEQUENCE_LEN:
        seq.append(np.zeros(FEATURE_DIM, dtype=np.float32))

    return np.array(seq[:SEQUENCE_LEN], dtype=np.float32)


# ─────────────────────────────────────────────────────────────────────────────
# Dataset stats
# ─────────────────────────────────────────────────────────────────────────────

def print_stats():
    root = Path(SAVE_DIR)
    if not root.exists():
        print("Dataset belum ada.")
        return

    bisindo = []
    asl     = []

    for d in sorted(root.iterdir()):
        if not d.is_dir():
            continue
        n = len(list(d.glob("seq_*.npy")))
        if d.name.startswith("ASL_"):
            asl.append((d.name[4:], n))
        else:
            bisindo.append((d.name, n))

    print(f"\n📊  Dataset Stats ({SAVE_DIR}/)\n")

    if bisindo:
        print(f"  🇮🇩  BISINDO ({len(bisindo)} kelas):")
        total = 0
        for name, n in bisindo:
            print(f"    {name:<20} {n:>4} sequences")
            total += n
        print(f"    {'TOTAL':<20} {total:>4}")

    if asl:
        print(f"\n  🇺🇸  ASL ({len(asl)} kelas):")
        total = 0
        for name, n in asl:
            print(f"    {name:<20} {n:>4} sequences")
            total += n
        print(f"    {'TOTAL':<20} {total:>4}")

    print()


# ─────────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="KawanIsyarat — ASL Dataset Preparation",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Contoh:
  # Google ASL Signs (parquet, landmark sudah di-extract):
  python prepare_asl_dataset.py google --data-dir ./asl-signs --list
  python prepare_asl_dataset.py google --data-dir ./asl-signs --signs hello yes no deaf help
  python prepare_asl_dataset.py google --data-dir ./asl-signs --default
  python prepare_asl_dataset.py google --data-dir ./asl-signs --all --max 100

  # WLASL (video MP4):
  python prepare_asl_dataset.py wlasl --data-dir ./wlasl2000 --signs hello yes no

  # Lihat stats
  python prepare_asl_dataset.py stats
        """
    )
    sub = parser.add_subparsers(dest="mode")

    # google
    gp = sub.add_parser("google", help="Proses Google ASL Signs (Kaggle parquet)")
    gp.add_argument("--data-dir", required=True, help="Folder hasil extract Kaggle")
    gp.add_argument("--signs",    nargs="+",     help="Daftar kata (misal: hello yes no)")
    gp.add_argument("--default",  action="store_true",
                    help=f"Proses {len(DEFAULT_SIGNS)} kata default yang relevan")
    gp.add_argument("--all",      action="store_true", help="Proses semua 250 kata")
    gp.add_argument("--max",      type=int, default=200,
                    help="Maksimal sequences per kata (default: 200)")
    gp.add_argument("--list",     action="store_true", help="Tampilkan semua kata tersedia")

    # wlasl
    wp = sub.add_parser("wlasl", help="Proses WLASL dataset (video MP4)")
    wp.add_argument("--data-dir", required=True)
    wp.add_argument("--signs",    nargs="+",   help="Daftar kata")
    wp.add_argument("--default",  action="store_true")
    wp.add_argument("--max",      type=int, default=50)

    # stats
    sub.add_parser("stats", help="Tampilkan ringkasan dataset")

    args = parser.parse_args()

    if args.mode == "google":
        if args.list:
            list_google_asl_signs(args.data_dir)
            return
        if args.all:
            # Load semua kata dari train.csv
            df    = pd.read_csv(Path(args.data_dir) / "train.csv")
            signs = sorted(df['sign'].unique().tolist())
        elif args.default:
            signs = DEFAULT_SIGNS
        elif args.signs:
            signs = [s.lower() for s in args.signs]
        else:
            parser.error("Pilih --signs, --default, atau --all")
            return
        process_google_asl(args.data_dir, signs, args.max)

    elif args.mode == "wlasl":
        if args.default:
            signs = DEFAULT_SIGNS
        elif args.signs:
            signs = [s.lower() for s in args.signs]
        else:
            parser.error("Pilih --signs atau --default")
            return
        process_wlasl(args.data_dir, signs, args.max)

    elif args.mode == "stats":
        print_stats()

    else:
        parser.print_help()


if __name__ == "__main__":
    main()
