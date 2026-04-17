#!/usr/bin/env python3
"""
kaggle_prepare_asl_subset.py
============================
Versi untuk dijalankan di Kaggle Notebook — TANPA CLI/argparse.

PENTING: Feature format seragam dengan data_collector.py (94 floats):
  [0:42]   = Tangan KANAN: 21 × (x,y), nose-centered + shoulder-normalized
  [42:84]  = Tangan KIRI:  21 × (x,y), nose-centered + shoulder-normalized
  [84:94]  = Pose anchor:  5 titik × (x,y)
               [84:86] = nose, [86:88] = l_shoulder, [88:90] = r_shoulder
               [90:92] = l_ear, [92:94] = r_ear

Dataset input (tambahkan sebagai Kaggle Dataset input):
  - Competition: asl-signs  → /kaggle/input/asl-signs/

Output:
  /kaggle/working/dataset/ASL_<SIGN>/seq_XXXX.npy  shape=(30, 94)
  /kaggle/working/asl_subset_labels.json

Cara pakai di Kaggle Notebook:
  Cell 1:  %run kaggle_prepare_asl_subset.py   # atau paste / import
  Cell 2:  sanity_check()
  Cell 3:  run_pipeline()
  Cell 4:  X, y = load_dataset_for_training()
  Cell 5:  model, history = train_model(X, y)
  Cell 6:  convert_to_tflite(model)
"""

# ── Imports ───────────────────────────────────────────────────────────────────
import json
import os
from pathlib import Path

import numpy as np
import pandas as pd

# ── Kaggle paths ──────────────────────────────────────────────────────────────
TRAIN_DIR  = Path("/kaggle/input/asl-signs")
TRAIN_CSV  = TRAIN_DIR / "train.csv"
SIGN_MAP   = TRAIN_DIR / "sign_to_prediction_index_map.json"

OUT_DIR    = Path("/kaggle/working/dataset")
LABELS_OUT = Path("/kaggle/working/asl_subset_labels.json")
MODEL_OUT  = Path("/kaggle/working/asl_kawan_model.keras")
TFLITE_OUT = Path("/kaggle/working/asl_kawan_model.tflite")

# ── Constants — SERAGAM dengan data_collector.py ──────────────────────────────
SEQUENCE_LEN = 30
FEATURE_DIM  = 94   # ← sama dengan data_collector.py

# Pose landmark indices (MediaPipe Pose)
POSE_NOSE       = 0
POSE_L_EAR      = 7
POSE_R_EAR      = 8
POSE_L_SHOULDER = 11
POSE_R_SHOULDER = 12
POSE_ANCHOR_IDX = [POSE_NOSE, POSE_L_SHOULDER, POSE_R_SHOULDER,
                   POSE_L_EAR, POSE_R_EAR]   # 5 titik → 10 floats

# ── Subset kata ASL yang tersedia di Kaggle & relevan untuk BISINDO ─────────
# Diverifikasi dari sign_to_prediction_index_map.json (250 kata)
# Prioritas: daily communication untuk Tuli-hearing interaction

# Priority 1 — Sapaan, keluarga, aktivitas dasar, emosi, tempat, waktu
DEFAULT_SIGNS_P1 = [
    # Sapaan & courtesy
    "hello", "bye", "thankyou", "please", "yes", "no",
    # Keluarga
    "mom", "dad", "brother", "grandma", "grandpa", "uncle",
    "girl", "boy", "man", "person", "child",
    # Aktivitas dasar
    "drink", "sleep", "go", "look", "listen", "talk",
    "give", "open", "close", "wake", "wait", "find", "think",
    # Kondisi & emosi
    "happy", "sad", "cry", "mad", "sick", "hungry", "thirsty", "fine",
    # Tempat
    "home", "room", "outside", "store", "potty",
    # Waktu
    "morning", "night", "tomorrow", "yesterday", "now", "later",
]

# Priority 2 — Kata sifat, tanya, pronoun, benda sehari-hari
DEFAULT_SIGNS_P2 = [
    # Kata tanya & fungsi
    "where", "who", "why", "not", "have", "can", "because",
    # Kata sifat
    "bad", "clean", "dirty", "hot", "wet", "fast",
    "quiet", "loud", "many", "same", "pretty", "old",
    # Pronoun
    "hesheit", "weus", "minemy", "yourself",
    # Makanan & benda
    "food", "milk", "water", "book", "car",
    "chair", "table", "pen", "pencil", "shoe", "shirt",
    # Alam
    "rain", "sun", "moon", "tree", "flower",
    # Aktivitas tambahan
    "read", "touch", "jump", "dance", "cut", "make",
    # Tambahan berguna
    "shower", "time", "that", "there", "if", "for",
]

# Combined — dipakai untuk training
DEFAULT_SIGNS = DEFAULT_SIGNS_P1 + DEFAULT_SIGNS_P2

# ⚠️  TIDAK ADA di dataset (jangan dipakai):
# sorry, father, mother, friend, name, deaf, hearing,
# eat, come, stop, want, need, school, hospital, bathroom, today, pain
# one, two, three, four, five  (angka tidak ada di dataset)

# ─────────────────────────────────────────────────────────────────────────────
# Feature extraction — format identik dengan data_collector.py
# ─────────────────────────────────────────────────────────────────────────────
# ASL Kaggle dataset: parquet berisi kolom frame | type | landmark_index | x | y | z
# type values: 'face' | 'left_hand' | 'right_hand' | 'pose'
# Kita ambil: right_hand (21 lm), left_hand (21 lm), pose (33 lm)
#
# Normalisasi nose-centered + shoulder-normalized (sama dengan data_collector.py):
#   output[i] = (raw_x_or_y - nose_pos) / shoulder_width

def _extract_features_from_frame_df(fdf: pd.DataFrame) -> np.ndarray:
    """
    Satu frame parquet (fdf) → 94-float feature vector.
    Format identik dengan data_collector.py extract_features().
    """
    out = np.zeros(FEATURE_DIM, dtype=np.float32)

    def get_lm(ltype: str, n: int) -> np.ndarray | None:
        """Ambil n landmark dari frame df, return (n,2) atau None."""
        sub = fdf[fdf['type'] == ltype].sort_values('landmark_index')
        if len(sub) < n:
            return None
        return sub[['x', 'y']].values[:n].astype(np.float32)

    pose       = get_lm('pose',       33)
    right_hand = get_lm('right_hand', 21)
    left_hand  = get_lm('left_hand',  21)

    # ── Pose anchors & normalization params ───────────────────────────────────
    nose_x, nose_y = 0.5, 0.5
    shoulder_w     = 0.3
    has_pose       = False

    if pose is not None:
        nose_x     = pose[POSE_NOSE, 0]
        nose_y     = pose[POSE_NOSE, 1]
        lsx        = pose[POSE_L_SHOULDER, 0]
        rsx        = pose[POSE_R_SHOULDER, 0]
        shoulder_w = max(abs(rsx - lsx), 1e-6)
        has_pose   = True

        # Simpan 5 anchor pose (nose-centered, shoulder-normalized) → [84:94]
        for i, idx in enumerate(POSE_ANCHOR_IDX):
            out[84 + i * 2]     = (pose[idx, 0] - nose_x) / shoulder_w
            out[84 + i * 2 + 1] = (pose[idx, 1] - nose_y) / shoulder_w

    # ── Hand landmarks (nose-centered + shoulder-normalized) ──────────────────
    for lm_data, base in [(right_hand, 0), (left_hand, 42)]:
        if lm_data is None:
            continue
        for j in range(21):
            out[base + j * 2]     = (lm_data[j, 0] - nose_x) / shoulder_w
            out[base + j * 2 + 1] = (lm_data[j, 1] - nose_y) / shoulder_w

    return out


def load_parquet_sequence(parquet_path: str) -> np.ndarray:
    """
    Load satu parquet file → (SEQUENCE_LEN, FEATURE_DIM) float32.
    Subsample uniform ke SEQUENCE_LEN frame, zero-pad jika kurang.
    """
    df     = pd.read_parquet(parquet_path)
    frames = sorted(df['frame'].unique())
    n      = len(frames)

    if n == 0:
        return np.zeros((SEQUENCE_LEN, FEATURE_DIM), dtype=np.float32)

    # Uniform subsample
    if n >= SEQUENCE_LEN:
        indices    = np.linspace(0, n - 1, SEQUENCE_LEN, dtype=int)
        sel_frames = [frames[i] for i in indices]
    else:
        sel_frames = frames

    seq = []
    for fid in sel_frames:
        fdf  = df[df['frame'] == fid]
        feat = _extract_features_from_frame_df(fdf)
        seq.append(feat)

    # Zero-pad
    while len(seq) < SEQUENCE_LEN:
        seq.append(np.zeros(FEATURE_DIM, dtype=np.float32))

    return np.array(seq[:SEQUENCE_LEN], dtype=np.float32)  # (30, 94)


# ─────────────────────────────────────────────────────────────────────────────
# Pipeline utama
# ─────────────────────────────────────────────────────────────────────────────

def sanity_check():
    """Verifikasi semua path dan hitung coverage DEFAULT_SIGNS."""
    print("\n🔧  Sanity Check\n")

    paths = {
        "train.csv"                    : TRAIN_CSV,
        "sign_to_prediction_index_map" : SIGN_MAP,
        "train_landmark_files/"        : TRAIN_DIR / "train_landmark_files",
    }
    for name, p in paths.items():
        print(f"  {'✅' if p.exists() else '❌'}  {name:<35}  {p}")

    if TRAIN_CSV.exists():
        df     = pd.read_csv(TRAIN_CSV)
        avail  = set(df['sign'].unique())
        found  = [s for s in DEFAULT_SIGNS if s in avail]
        not_found = [s for s in DEFAULT_SIGNS if s not in avail]

        counts = df[df['sign'].isin(found)]['sign'].value_counts()
        total_rows = counts.sum()

        print(f"\n  train.csv   : {len(df):,} baris total, {df['sign'].nunique()} kata")
        print(f"  DEFAULT_SIGNS overlap : {len(found)}/{len(DEFAULT_SIGNS)} kata")
        print(f"  Baris akan diproses  : {total_rows:,} ({total_rows/len(df)*100:.1f}% dari total)")
        if not_found:
            print(f"  ⚠  Tidak tersedia    : {not_found}")

        print(f"\n  Distribusi per kata (DEFAULT_SIGNS):")
        for sign in DEFAULT_SIGNS:
            n      = counts.get(sign, 0)
            status = "✅" if n > 0 else "❌"
            print(f"    {status}  {sign:<15} {n:>4} sequences")


def check_available_signs(signs=DEFAULT_SIGNS):
    """Return (available, missing) dari train.csv."""
    df    = pd.read_csv(TRAIN_CSV)
    avail = set(df['sign'].unique())
    return [s for s in signs if s in avail], [s for s in signs if s not in avail]


def process_subset(
    signs         = DEFAULT_SIGNS,
    max_per_sign  : int = 200,
    min_valid_frames: int = 5,
) -> dict:
    """
    Load parquet sesuai DEFAULT_SIGNS → simpan sebagai seq_XXXX.npy (30,94).

    Returns: {sign: {"total_rows": int, "saved": int}}
    """
    available, missing = check_available_signs(signs)
    if missing:
        print(f"⚠  Tidak tersedia: {missing}")
    if not available:
        print("✗  Tidak ada kata yang bisa diproses.")
        return {}

    df        = pd.read_csv(TRAIN_CSV)
    df_subset = df[df['sign'].isin(available)].copy()

    print(f"\n📋  Subset: {len(df_subset):,} baris ({len(df_subset)/len(df)*100:.1f}% dari {len(df):,} total)\n")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    stats = {}

    for sign in available:
        rows      = df_subset[df_subset['sign'] == sign].head(max_per_sign)
        save_path = OUT_DIR / f"ASL_{sign.upper()}"
        save_path.mkdir(parents=True, exist_ok=True)
        existing  = len(list(save_path.glob("seq_*.npy")))

        print(f"  [{sign:<15}]  {len(rows):>3} rows ...", end=" ", flush=True)
        saved = 0

        for _, row in rows.iterrows():
            parquet_path = TRAIN_DIR / row['path']
            if not parquet_path.exists():
                continue

            seq          = load_parquet_sequence(str(parquet_path))
            valid_frames = np.any(seq != 0, axis=1).sum()

            if valid_frames < min_valid_frames:
                continue

            np.save(save_path / f"seq_{existing + saved:04d}.npy", seq)
            saved += 1

        print(f"→  {saved} tersimpan")
        stats[sign] = {"total_rows": len(rows), "saved": saved}

    return stats


def build_label_map(signs: list) -> dict:
    """
    Buat label map {sign: index} dan simpan ke JSON.
    Index 0-based, urutan sesuai `signs` (biasanya = DEFAULT_SIGNS yang berhasil).
    """
    label_to_index = {sign: idx for idx, sign in enumerate(signs)}

    # Sertakan index Kaggle asli (opsional, berguna untuk referensi)
    kaggle_map = {}
    if SIGN_MAP.exists():
        with open(SIGN_MAP) as f:
            kaggle_map = json.load(f)

    out = {
        "label_to_index"       : label_to_index,
        "index_to_label"       : {str(v): k for k, v in label_to_index.items()},
        "kaggle_original_index": {s: kaggle_map.get(s) for s in signs if s in kaggle_map},
        "num_classes"          : len(signs),
        "signs"                : signs,
        "feature_dim"          : FEATURE_DIM,    # 94 — seragam dengan data_collector.py
        "sequence_len"         : SEQUENCE_LEN,   # 30
    }

    with open(LABELS_OUT, "w") as f:
        json.dump(out, f, indent=2)

    print(f"\n✅  Label map ({len(signs)} kelas) → {LABELS_OUT}")
    return out


def print_dataset_stats(signs=DEFAULT_SIGNS):
    """Tampilkan jumlah sequence per sign."""
    print(f"\n📊  Dataset Stats  ({OUT_DIR})\n")
    total_all = 0
    for sign in signs:
        d = OUT_DIR / f"ASL_{sign.upper()}"
        n = len(list(d.glob("seq_*.npy"))) if d.exists() else 0
        total_all += n
        bar    = "█" * (n // 10)
        status = "✅" if n > 0 else "❌"
        print(f"  {status}  {sign:<15} {n:>4}  {bar}")
    kelas_ok = sum(1 for s in signs
                   if (OUT_DIR / f"ASL_{s.upper()}").exists()
                   and len(list((OUT_DIR / f"ASL_{s.upper()}").glob("seq_*.npy"))) > 0)
    print(f"\n     TOTAL  {total_all:>5} sequences  |  {kelas_ok}/{len(signs)} kelas")


def run_pipeline(signs=DEFAULT_SIGNS, max_per_sign: int = 200):
    """
    Entry point utama.
    Proses subset dari ASL Kaggle → npy files → label map.

    Contoh:
        run_pipeline()                              # semua DEFAULT_SIGNS
        run_pipeline(signs=["hello","yes","no"])    # subset kecil utk test
        run_pipeline(max_per_sign=50)               # cepat, 50 seq/kata
    """
    print("=" * 62)
    print("  KawanIsyarat — ASL Subset Pipeline")
    print(f"  Signs     : {len(signs)} kata")
    print(f"  Max/sign  : {max_per_sign} sequences")
    print(f"  Feat dim  : {FEATURE_DIM} (nose-centered, shoulder-norm)")
    print(f"  Input     : {TRAIN_DIR}")
    print(f"  Output    : {OUT_DIR}")
    print("=" * 62)

    stats = process_subset(signs=signs, max_per_sign=max_per_sign)

    processed_signs = [s for s, v in stats.items() if v["saved"] > 0]
    label_map       = build_label_map(processed_signs)
    print_dataset_stats(processed_signs)

    print(f"\n🎉  Pipeline selesai!")
    print(f"   Selanjutnya: X, y = load_dataset_for_training()")
    return label_map, stats


# ─────────────────────────────────────────────────────────────────────────────
# Load dataset → siap training
# ─────────────────────────────────────────────────────────────────────────────

def load_dataset_for_training(
    dataset_dir: Path = OUT_DIR,
    label_map_path: Path = LABELS_OUT,
) -> tuple[np.ndarray, np.ndarray, dict]:
    """
    Load semua seq_*.npy → (X, y) siap masuk model.

    Returns
    -------
    X         : (N, 30, 94)  float32
    y         : (N,)         int32
    label_map : dict dari JSON
    """
    if not label_map_path.exists():
        raise FileNotFoundError("Label map belum ada. Jalankan run_pipeline() dulu.")

    with open(label_map_path) as f:
        label_map = json.load(f)

    l2i   = label_map["label_to_index"]
    signs = label_map["signs"]

    X_list, y_list = [], []
    for sign in signs:
        folder = dataset_dir / f"ASL_{sign.upper()}"
        if not folder.exists():
            continue
        for npy_path in sorted(folder.glob("seq_*.npy")):
            seq = np.load(str(npy_path))          # (30, 94)
            X_list.append(seq)
            y_list.append(l2i[sign])

    if not X_list:
        raise ValueError("Dataset kosong. Jalankan run_pipeline() dulu.")

    X = np.array(X_list, dtype=np.float32)   # (N, 30, 94)
    y = np.array(y_list, dtype=np.int32)      # (N,)

    print(f"✅  Dataset: X={X.shape}  y={y.shape}")
    print(f"   {label_map['num_classes']} kelas, {len(X)} total sequences")

    # Tampilkan distribusi
    print("\n   Distribusi kelas:")
    for sign in signs:
        idx = l2i[sign]
        n   = int((y == idx).sum())
        bar = "█" * (n // 10)
        print(f"     [{idx:2d}] {sign:<15} {n:>4}  {bar}")

    return X, y, label_map


# ─────────────────────────────────────────────────────────────────────────────
# Training
# ─────────────────────────────────────────────────────────────────────────────
# Arsitektur: Conv1D + BiLSTM + Attention
# Identik dengan yang akan dipakai di Flutter (diinferensi via TFLite).
#
# Input shape  : (30, 94)   → satu sequence
# Output shape : (num_classes,)  → softmax probability
#
# Teknik augmentasi ringan:
#   - Gaussian noise pada koordinat tangan
#   - Time masking (drop beberapa frame → 0)
#   - Frame shift (geser sequence 1-3 frame)
#
# Train/Val/Test split: 70/15/15 (stratified per kelas)

def add_temporal_derivatives(X: np.ndarray) -> np.ndarray:
    """
    Tambahkan velocity & acceleration sebagai feature tambahan.
    Input  : (N, 30, 94)
    Output : (N, 30, 282)  ← 94 × 3
    """
    velocity     = np.zeros_like(X)
    acceleration = np.zeros_like(X)

    velocity[:, 1:, :]     = X[:, 1:, :] - X[:, :-1, :]   # x[t] - x[t-1]
    acceleration[:, 2:, :] = X[:, 2:, :] - X[:, :-2, :]   # x[t] - x[t-2]

    return np.concatenate([X, velocity, acceleration], axis=-1)   # (N, 30, 282)


def augment_batch(X_batch: np.ndarray, noise_std: float = 0.01) -> np.ndarray:
    """
    Augmentasi sederhana untuk satu batch:
      1. Gaussian noise pada coords tangan [0:84]
      2. Time masking: random 1-3 frame di-zero
    """
    X = X_batch.copy()
    N = X.shape[0]

    # 1. Gaussian noise
    noise = np.random.normal(0, noise_std, X[:, :, :84].shape).astype(np.float32)
    X[:, :, :84] += noise

    # 2. Time masking
    for i in range(N):
        n_mask = np.random.randint(0, 4)   # 0–3 frame
        if n_mask > 0:
            starts = np.random.randint(0, SEQUENCE_LEN - n_mask, size=1)
            for s in starts:
                X[i, s:s + n_mask, :] = 0.0

    return X


def build_model(num_classes: int, input_dim: int = 282) -> "tf.keras.Model":
    """
    Conv1D + BiLSTM + Self-Attention.
    input_dim default = 282 (94 × 3, setelah add_temporal_derivatives).
    """
    import tensorflow as tf
    from tensorflow.keras import layers, Model

    inp = layers.Input(shape=(SEQUENCE_LEN, input_dim), name="sequence_input")

    # ── Conv1D block ──────────────────────────────────────────────────────────
    x = layers.Conv1D(64, kernel_size=3, padding='same', activation='relu')(inp)
    x = layers.BatchNormalization()(x)
    x = layers.Conv1D(64, kernel_size=3, padding='same', activation='relu')(x)
    x = layers.BatchNormalization()(x)
    x = layers.Dropout(0.3)(x)

    # ── BiLSTM ────────────────────────────────────────────────────────────────
    x = layers.Bidirectional(layers.LSTM(128, return_sequences=True))(x)
    x = layers.Dropout(0.3)(x)
    x = layers.Bidirectional(layers.LSTM(64,  return_sequences=True))(x)

    # ── Self-Attention (dot-product) ──────────────────────────────────────────
    attn = layers.Dense(1, activation='tanh')(x)          # (batch, 30, 1)
    attn = layers.Flatten()(attn)                          # (batch, 30)
    attn = layers.Activation('softmax', name='attention_weights')(attn)
    attn = layers.RepeatVector(128)(attn)                  # (batch, 128, 30) ← 64*2 BiLSTM
    attn = layers.Permute([2, 1])(attn)                    # (batch, 30, 128)
    x    = layers.Multiply()([x, attn])
    x    = layers.Lambda(lambda t: tf.reduce_sum(t, axis=1))(x)  # (batch, 128)

    # ── Classifier head ───────────────────────────────────────────────────────
    x   = layers.Dense(128, activation='relu')(x)
    x   = layers.Dropout(0.4)(x)
    out = layers.Dense(num_classes, activation='softmax', name='predictions')(x)

    model = Model(inputs=inp, outputs=out)
    return model


def train_model(
    X: np.ndarray,
    y: np.ndarray,
    label_map: dict,
    epochs: int     = 80,
    batch_size: int = 32,
    use_derivatives: bool = True,
) -> tuple:
    """
    Training model KawanIsyarat dari ASL subset.

    Parameters
    ----------
    X              : (N, 30, 94)  — output load_dataset_for_training()
    y              : (N,)
    label_map      : dict dari JSON
    epochs         : jumlah epoch training (default: 80)
    batch_size     : ukuran batch (default: 32)
    use_derivatives: tambahkan velocity+acceleration → input 282-dim (default: True)

    Returns
    -------
    model   : tf.keras.Model sudah di-train
    history : History object
    """
    import tensorflow as tf
    from sklearn.model_selection import train_test_split

    num_classes = label_map["num_classes"]
    print(f"\n🧠  Training — {num_classes} kelas, {len(X)} sequences")

    # ── Tambah temporal derivatives ───────────────────────────────────────────
    if use_derivatives:
        print("   Menambahkan velocity + acceleration...")
        X = add_temporal_derivatives(X)   # (N, 30, 282)
    input_dim = X.shape[-1]
    print(f"   Input shape: ({SEQUENCE_LEN}, {input_dim})")

    # ── Split 70/15/15 stratified ─────────────────────────────────────────────
    X_train, X_temp, y_train, y_temp = train_test_split(
        X, y, test_size=0.30, random_state=42, stratify=y)
    X_val, X_test, y_val, y_test = train_test_split(
        X_temp, y_temp, test_size=0.50, random_state=42, stratify=y_temp)

    print(f"\n   Split:")
    print(f"     Train : {len(X_train):>5} ({len(X_train)/len(X)*100:.0f}%)")
    print(f"     Val   : {len(X_val):>5} ({len(X_val)/len(X)*100:.0f}%)")
    print(f"     Test  : {len(X_test):>5} ({len(X_test)/len(X)*100:.0f}%)")

    # ── One-hot encode ────────────────────────────────────────────────────────
    y_train_oh = tf.keras.utils.to_categorical(y_train, num_classes)
    y_val_oh   = tf.keras.utils.to_categorical(y_val,   num_classes)

    # ── Build model ───────────────────────────────────────────────────────────
    model = build_model(num_classes=num_classes, input_dim=input_dim)
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=1e-3),
        loss='categorical_crossentropy',
        metrics=['accuracy'],
    )
    model.summary()

    # ── Callbacks ─────────────────────────────────────────────────────────────
    callbacks = [
        tf.keras.callbacks.EarlyStopping(
            monitor='val_accuracy', patience=15,
            restore_best_weights=True, verbose=1),
        tf.keras.callbacks.ReduceLROnPlateau(
            monitor='val_loss', factor=0.5,
            patience=7, min_lr=1e-6, verbose=1),
        tf.keras.callbacks.ModelCheckpoint(
            str(MODEL_OUT), monitor='val_accuracy',
            save_best_only=True, verbose=1),
    ]

    # ── Training loop dengan augmentasi ──────────────────────────────────────
    # Augmentasi manual per epoch (lebih fleksibel dari ImageDataGenerator)
    print(f"\n🚀  Mulai training {epochs} epoch ...\n")
    history = {"loss": [], "accuracy": [], "val_loss": [], "val_accuracy": []}

    for epoch in range(epochs):
        # Augment train set per epoch
        X_aug = augment_batch(X_train, noise_std=0.008)

        # Shuffle
        idx    = np.random.permutation(len(X_aug))
        X_aug  = X_aug[idx]
        y_aug  = y_train_oh[idx]

        h = model.fit(
            X_aug, y_aug,
            validation_data=(X_val, y_val_oh),
            epochs=1,
            batch_size=batch_size,
            verbose=0,
            callbacks=[callbacks[1]],    # ReduceLROnPlateau saja
        )
        history["loss"].append(h.history["loss"][0])
        history["accuracy"].append(h.history["accuracy"][0])
        history["val_loss"].append(h.history["val_loss"][0])
        history["val_accuracy"].append(h.history["val_accuracy"][0])

        # Print setiap 5 epoch
        if (epoch + 1) % 5 == 0 or epoch == 0:
            print(f"  Epoch {epoch+1:3d}/{epochs}  "
                  f"loss={history['loss'][-1]:.4f}  acc={history['accuracy'][-1]:.4f}  "
                  f"val_loss={history['val_loss'][-1]:.4f}  val_acc={history['val_accuracy'][-1]:.4f}")

        # Early stopping manual
        best_val = max(history["val_accuracy"])
        no_improve = sum(1 for v in history["val_accuracy"][-15:] if v < best_val)
        if len(history["val_accuracy"]) > 15 and no_improve >= 15:
            print(f"  Early stopping di epoch {epoch+1}")
            break

    # ── Evaluasi pada test set ────────────────────────────────────────────────
    print(f"\n📊  Evaluasi pada test set ({len(X_test)} sequences):")

    # Reload best model
    if MODEL_OUT.exists():
        model = tf.keras.models.load_model(str(MODEL_OUT))

    y_pred      = np.argmax(model.predict(X_test, verbose=0), axis=1)
    test_acc    = (y_pred == y_test).mean()
    print(f"   Test Accuracy : {test_acc:.4f} ({test_acc*100:.2f}%)")

    # Per-class accuracy
    index_to_label = label_map["index_to_label"]
    print(f"\n   Per-kelas accuracy:")
    for idx in range(num_classes):
        mask = y_test == idx
        if mask.sum() == 0:
            continue
        acc_k = (y_pred[mask] == idx).mean()
        label = index_to_label[str(idx)]
        bar   = "█" * int(acc_k * 20)
        print(f"     [{idx:2d}] {label:<15}  {acc_k:.2f}  {bar}")

    model.save(str(MODEL_OUT))
    print(f"\n✅  Model tersimpan → {MODEL_OUT}")

    return model, history


# ─────────────────────────────────────────────────────────────────────────────
# Convert ke TFLite (untuk Flutter)
# ─────────────────────────────────────────────────────────────────────────────

def convert_to_tflite(
    model=None,
    quantize: bool = True,
    X_representative: np.ndarray = None,
):
    """
    Konversi model Keras → TFLite.
    Gunakan quantize=True agar model kecil (int8) untuk on-device inference.

    Parameters
    ----------
    model             : tf.keras.Model (jika None, load dari MODEL_OUT)
    quantize          : full int8 quantization (butuh X_representative)
    X_representative  : sample 100-200 sequences untuk kalibrasi quantization
    """
    import tensorflow as tf

    if model is None:
        model = tf.keras.models.load_model(str(MODEL_OUT))
        print(f"📦  Loaded model dari {MODEL_OUT}")

    converter = tf.lite.TFLiteConverter.from_keras_model(model)

    if quantize and X_representative is not None:
        print("   Menggunakan full int8 quantization...")

        # Pastikan derivatives sudah ditambahkan jika model memakainya
        if X_representative.shape[-1] == FEATURE_DIM:
            X_repr = add_temporal_derivatives(X_representative)
        else:
            X_repr = X_representative

        def rep_gen():
            for i in range(min(200, len(X_repr))):
                yield [X_repr[i:i+1].astype(np.float32)]

        converter.optimizations = [tf.lite.Optimize.DEFAULT]
        converter.representative_dataset = rep_gen
        converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
        converter.inference_input_type  = tf.float32   # tetap float untuk kemudahan Flutter
        converter.inference_output_type = tf.float32
    else:
        converter.optimizations = [tf.lite.Optimize.DEFAULT]   # float16 fallback
        print("   Menggunakan float16 optimization...")

    tflite_model = converter.convert()

    with open(TFLITE_OUT, "wb") as f:
        f.write(tflite_model)

    size_mb = len(tflite_model) / 1024 / 1024
    print(f"\n✅  TFLite tersimpan → {TFLITE_OUT}  ({size_mb:.2f} MB)")
    print(f"\n   Langkah berikutnya:")
    print(f"   1. Download TFLite + label JSON dari /kaggle/working/")
    print(f"   2. Copy ke Flutter: assets/models/asl_kawan_model.tflite")
    print(f"   3. Copy ke Flutter: assets/models/asl_subset_labels.json")

    return TFLITE_OUT


# ─────────────────────────────────────────────────────────────────────────────
# One-shot run
# ─────────────────────────────────────────────────────────────────────────────
# Copy kode berikut ke sel-sel Kaggle Notebook:
#
#   # Sel 1 — Setup & verifikasi
#   sanity_check()
#
#   # Sel 2 — Proses parquet → npy (beberapa menit)
#   label_map, stats = run_pipeline(max_per_sign=200)
#
#   # Sel 3 — Load untuk training
#   X, y, label_map = load_dataset_for_training()
#
#   # Sel 4 — Training (dengan derivatives, train/val/test split otomatis)
#   model, history = train_model(X, y, label_map, epochs=80)
#
#   # Sel 5 — Convert TFLite
#   convert_to_tflite(model, quantize=True, X_representative=X[:200])
# ─────────────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    sanity_check()
