#!/usr/bin/env python3
"""
prepare_sibi_alphabet.py — Ekstrak landmark + Train Model SIBI Alphabet (Kaggle Notebook)
=========================================================================================
Dataset: https://www.kaggle.com/datasets/alvinbintang/sibi-dataset/data
Struktur: sibi-dataset/A/*.jpg, sibi-dataset/B/*.jpg, ..., sibi-dataset/Z/*.jpg

Output:
  /kaggle/working/dataset_alphabet/<HURUF>/landmarks.npy  shape=(N, 42)
  /kaggle/working/sibi_alphabet_model.tflite
  /kaggle/working/sibi_alphabet_labels.json

42 floats = 21 hand landmarks × (x, y), bbox-normalized (Boháček)
Model 1: Dense classifier (bukan LSTM — huruf statis).
J dan Z bersifat dinamis (gerakan) → skip.

Usage (Kaggle Notebook):
  # Cell 1: Extract landmarks
  !python prepare_sibi_alphabet.py extract

  # Cell 2: Train model
  !python prepare_sibi_alphabet.py train

  # Cell 3: Stats
  !python prepare_sibi_alphabet.py stats

  # Atau semuanya sekaligus:
  !python prepare_sibi_alphabet.py all
"""

import argparse
import json
import string
import cv2
import mediapipe as mp
import numpy as np
from pathlib import Path
    
# ─── Kaggle paths ────────────────────────────────────────────────────────────
INPUT_DIR = Path("/kaggle/input/datasets/alvinbintang/sibi-dataset/SIBI")
WORKING_DIR = Path("/kaggle/working")
SAVE_DIR = WORKING_DIR / "dataset_alphabet"

# ─── Constants ───────────────────────────────────────────────────────────────
DYNAMIC_LETTERS = {"J", "Z"}
NUM_FEATURES = 42  # 21 landmarks × 2 (x, y)

mp_hands = mp.solutions.hands


# ═══════════════════════════════════════════════════════════════════════════════
#  STEP 1: EXTRACT LANDMARKS
# ═══════════════════════════════════════════════════════════════════════════════

def normalize_hand_shape(landmarks_21) -> np.ndarray:
    """Boháček bbox-normalization: 21 landmarks → 42 floats."""
    coords = np.array([[lm.x, lm.y] for lm in landmarks_21], dtype=np.float32)
    min_x, min_y = coords[:, 0].min(), coords[:, 1].min()
    max_x, max_y = coords[:, 0].max(), coords[:, 1].max()
    w = max(max_x - min_x, 1e-6)
    h = max(max_y - min_y, 1e-6)
    norm = np.zeros_like(coords)
    norm[:, 0] = (coords[:, 0] - min_x) / w
    norm[:, 1] = (coords[:, 1] - min_y) / h
    return norm.flatten()  # 42 floats


def normalize_from_coords(coords: np.ndarray) -> np.ndarray:
    """Boháček bbox-normalization dari raw coords array (21, 2) → 42 floats."""
    min_x, min_y = coords[:, 0].min(), coords[:, 1].min()
    max_x, max_y = coords[:, 0].max(), coords[:, 1].max()
    w = max(max_x - min_x, 1e-6)
    h = max(max_y - min_y, 1e-6)
    norm = np.zeros_like(coords)
    norm[:, 0] = (coords[:, 0] - min_x) / w
    norm[:, 1] = (coords[:, 1] - min_y) / h
    return norm.flatten()


def augment_landmarks(landmarks_21) -> list[np.ndarray]:
    """Generate augmented versions dari 21 landmarks.

    Augmentasi pada KOORDINAT (bukan pixel), sehingga hasilnya tetap
    konsisten dengan Boháček normalization.

    Returns list of 42-float feature vectors (termasuk original).
    """
    coords = np.array([[lm.x, lm.y] for lm in landmarks_21], dtype=np.float32)
    results = []

    # --- 1. Original ---
    results.append(normalize_from_coords(coords))

    # --- 2. Flip horizontal (mirror kiri ↔ kanan) ---
    flipped = coords.copy()
    flipped[:, 0] = 1.0 - flipped[:, 0]
    results.append(normalize_from_coords(flipped))

    # --- 3. Rotasi kecil: ±5°, ±10°, ±15° ---
    cx, cy = coords[:, 0].mean(), coords[:, 1].mean()
    for angle_deg in [-15, -10, -5, 5, 10, 15]:
        rad = np.radians(angle_deg)
        cos_a, sin_a = np.cos(rad), np.sin(rad)
        rotated = coords.copy()
        dx = rotated[:, 0] - cx
        dy = rotated[:, 1] - cy
        rotated[:, 0] = dx * cos_a - dy * sin_a + cx
        rotated[:, 1] = dx * sin_a + dy * cos_a + cy
        results.append(normalize_from_coords(rotated))

    # --- 4. Rotasi + flip (6 rotasi × flip = 6 tambahan) ---
    for angle_deg in [-15, -10, -5, 5, 10, 15]:
        rad = np.radians(angle_deg)
        cos_a, sin_a = np.cos(rad), np.sin(rad)
        rotated = coords.copy()
        dx = rotated[:, 0] - cx
        dy = rotated[:, 1] - cy
        rotated[:, 0] = dx * cos_a - dy * sin_a + cx
        rotated[:, 1] = dx * sin_a + dy * cos_a + cy
        rotated[:, 0] = 1.0 - rotated[:, 0]  # flip
        results.append(normalize_from_coords(rotated))

    # --- 5. Scale jitter: ±5%, ±10% ---
    for scale in [0.90, 0.95, 1.05, 1.10]:
        scaled = coords.copy()
        scaled[:, 0] = (scaled[:, 0] - cx) * scale + cx
        scaled[:, 1] = (scaled[:, 1] - cy) * scale + cy
        results.append(normalize_from_coords(scaled))

    # --- 6. Translate jitter: geser kecil ---
    for dx, dy in [(-0.03, 0), (0.03, 0), (0, -0.03), (0, 0.03)]:
        shifted = coords.copy()
        shifted[:, 0] += dx
        shifted[:, 1] += dy
        results.append(normalize_from_coords(shifted))

    # --- 7. Noise: Gaussian kecil pada koordinat ---
    rng = np.random.default_rng()
    for _ in range(3):
        noisy = coords + rng.normal(0, 0.005, coords.shape).astype(np.float32)
        results.append(normalize_from_coords(noisy))

    return results  # total: 1 + 1 + 6 + 6 + 4 + 4 + 3 = 25 per sample


def process_letter(letter: str):
    """Proses semua gambar untuk satu huruf."""
    letter_dir = INPUT_DIR / letter
    if not letter_dir.exists():
        print(f"  ⚠  Folder tidak ditemukan: {letter_dir}")
        return 0

    exts = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}
    images = sorted(f for f in letter_dir.iterdir() if f.suffix.lower() in exts)

    if not images:
        print(f"  ⚠  Tidak ada gambar di: {letter_dir}")
        return 0

    save_path = SAVE_DIR / letter
    save_path.mkdir(parents=True, exist_ok=True)

    samples = []
    skipped = 0

    with mp_hands.Hands(
        static_image_mode=True,
        max_num_hands=1,
        min_detection_confidence=0.3,
    ) as hands:
        for img_path in images:
            img = cv2.imread(str(img_path))
            if img is None:
                skipped += 1
                continue

            if len(img.shape) == 2:
                img = cv2.cvtColor(img, cv2.COLOR_GRAY2RGB)
            else:
                img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)

            result = hands.process(img)

            if result.multi_hand_landmarks:
                lm = result.multi_hand_landmarks[0]
                augmented = augment_landmarks(lm.landmark)
                samples.extend(augmented)  # ~25 variasi per gambar
            else:
                skipped += 1

    if samples:
        arr = np.array(samples, dtype=np.float32)
        out_path = save_path / "landmarks.npy"
        np.save(out_path, arr)
        print(f"  ✓  {letter}:  {len(samples)} samples saved, "
              f"{skipped} skipped  →  {out_path}")
    else:
        print(f"  ✗  {letter}:  0 samples (semua {len(images)} gambar gagal detect)")

    return len(samples)


def extract_all(letters: list[str] | None = None):
    """Proses semua huruf (atau huruf tertentu)."""
    if letters is None:
        letters = sorted(set(string.ascii_uppercase) - DYNAMIC_LETTERS)
        print(f"\n🔤  Memproses {len(letters)} huruf statis (skip J, Z — dinamis)")
    else:
        letters = [l.upper() for l in letters]
        dynamic = [l for l in letters if l in DYNAMIC_LETTERS]
        if dynamic:
            print(f"  ⚠  {dynamic} bersifat dinamis — hasil mungkin kurang akurat")

    print(f"📂  Dataset: {INPUT_DIR}")
    print(f"💾  Output:  {SAVE_DIR}\n")

    total = 0
    for letter in letters:
        n = process_letter(letter)
        total += n

    print(f"\n{'─'*50}")
    print(f"  Total: {total} samples dari {len(letters)} huruf")
    print(f"{'─'*50}\n")
    return total


# ═══════════════════════════════════════════════════════════════════════════════
#  STEP 2: TRAIN MODEL
# ═══════════════════════════════════════════════════════════════════════════════

def load_dataset():
    """Load semua landmarks.npy → X, y, label_map."""
    X_all, y_all = [], []
    labels = sorted(
        d.name for d in SAVE_DIR.iterdir()
        if d.is_dir() and (d / "landmarks.npy").exists()
    )

    if not labels:
        raise FileNotFoundError(
            f"Tidak ada data di {SAVE_DIR}. Jalankan 'extract' dulu!")

    label_to_idx = {lbl: i for i, lbl in enumerate(labels)}

    for lbl in labels:
        arr = np.load(SAVE_DIR / lbl / "landmarks.npy")
        X_all.append(arr)
        y_all.extend([label_to_idx[lbl]] * len(arr))

    X = np.concatenate(X_all, axis=0)  # (N_total, 42)
    y = np.array(y_all, dtype=np.int32)

    print(f"📊  Dataset: {len(X)} samples, {len(labels)} kelas")
    print(f"    Labels: {labels}\n")

    return X, y, labels


def train_model(epochs: int = 150, batch_size: int = 256):
    """Train Dense classifier → export TFLite."""
    import tensorflow as tf
    from sklearn.model_selection import train_test_split

    X, y, labels = load_dataset()
    num_classes = len(labels)

    # Split
    X_train, X_val, y_train, y_val = train_test_split(
        X, y, test_size=0.15, random_state=42, stratify=y
    )
    print(f"🔀  Train: {len(X_train)}, Val: {len(X_val)}")

    # Online augmentation: noise ringan tambahan saat training
    def augment(x):
        noise = tf.random.normal(shape=tf.shape(x), mean=0.0, stddev=0.015)
        return x + noise

    train_ds = tf.data.Dataset.from_tensor_slices((X_train, y_train))
    train_ds = train_ds.shuffle(len(X_train)).batch(batch_size)
    train_ds = train_ds.map(lambda x, y: (augment(x), y))
    train_ds = train_ds.prefetch(tf.data.AUTOTUNE)

    val_ds = tf.data.Dataset.from_tensor_slices((X_val, y_val))
    val_ds = val_ds.batch(batch_size).prefetch(tf.data.AUTOTUNE)

    # Model: Dense classifier (deeper, lebih robust untuk dataset besar)
    model = tf.keras.Sequential([
        tf.keras.layers.Input(shape=(NUM_FEATURES,)),
        tf.keras.layers.Dense(512, activation="relu"),
        tf.keras.layers.BatchNormalization(),
        tf.keras.layers.Dropout(0.4),
        tf.keras.layers.Dense(256, activation="relu"),
        tf.keras.layers.BatchNormalization(),
        tf.keras.layers.Dropout(0.4),
        tf.keras.layers.Dense(128, activation="relu"),
        tf.keras.layers.BatchNormalization(),
        tf.keras.layers.Dropout(0.3),
        tf.keras.layers.Dense(64, activation="relu"),
        tf.keras.layers.Dropout(0.2),
        tf.keras.layers.Dense(num_classes, activation="softmax"),
    ])

    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=1e-3),
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"],
    )

    model.summary()

    # Callbacks
    callbacks = [
        tf.keras.callbacks.EarlyStopping(
            monitor="val_accuracy", patience=15, restore_best_weights=True
        ),
        tf.keras.callbacks.ReduceLROnPlateau(
            monitor="val_loss", factor=0.5, patience=5, min_lr=1e-6
        ),
    ]

    # Train
    print(f"\n🚀  Training {epochs} epochs...\n")
    history = model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=epochs,
        callbacks=callbacks,
        verbose=1,
    )

    # Final eval
    val_loss, val_acc = model.evaluate(val_ds, verbose=0)
    print(f"\n✅  Val accuracy: {val_acc:.4f}")

    # ─── Export TFLite ────────────────────────────────────────────────────
    tflite_path = WORKING_DIR / "sibi_alphabet_model.tflite"
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    # INT8 quantization dengan representative dataset
    def representative_dataset():
        for i in range(min(500, len(X_train))):
            yield [X_train[i:i+1].astype(np.float32)]

    converter.representative_dataset = representative_dataset
    converter.target_spec.supported_ops = [
        tf.lite.OpsSet.TFLITE_BUILTINS_INT8
    ]
    converter.inference_input_type = tf.uint8
    converter.inference_output_type = tf.uint8

    tflite_model = converter.convert()
    tflite_path.write_bytes(tflite_model)
    print(f"💾  TFLite INT8: {tflite_path} ({len(tflite_model)/1024:.1f} KB)")

    # ─── Export float32 TFLite juga (fallback) ────────────────────────────
    tflite_f32_path = WORKING_DIR / "sibi_alphabet_model_f32.tflite"
    converter_f32 = tf.lite.TFLiteConverter.from_keras_model(model)
    tflite_f32 = converter_f32.convert()
    tflite_f32_path.write_bytes(tflite_f32)
    print(f"💾  TFLite F32:  {tflite_f32_path} ({len(tflite_f32)/1024:.1f} KB)")

    # ─── Export labels JSON ───────────────────────────────────────────────
    labels_path = WORKING_DIR / "sibi_alphabet_labels.json"
    labels_path.write_text(json.dumps(labels, indent=2))
    print(f"🏷️  Labels: {labels_path}")

    # ─── Export Keras model juga (buat inspection) ────────────────────────
    keras_path = WORKING_DIR / "sibi_alphabet_model.keras"
    model.save(keras_path)
    print(f"📦  Keras:  {keras_path}")

    print(f"\n{'─'*50}")
    print(f"  🎉  Selesai! Copy file berikut ke Flutter assets:")
    print(f"       {tflite_path.name}")
    print(f"       {labels_path.name}")
    print(f"{'─'*50}\n")

    return model, history


# ═══════════════════════════════════════════════════════════════════════════════
#  STATS
# ═══════════════════════════════════════════════════════════════════════════════

def print_stats():
    """Tampilkan ringkasan dataset alfabet."""
    if not SAVE_DIR.exists():
        print("Dataset alphabet belum ada. Jalankan 'extract' dulu.")
        return

    print(f"\n📊  Dataset Alphabet ({SAVE_DIR}/)\n")
    total = 0
    per_class = {}
    for d in sorted(SAVE_DIR.iterdir()):
        if not d.is_dir():
            continue
        npy = d / "landmarks.npy"
        if npy.exists():
            arr = np.load(npy)
            n = len(arr)
            status = "✓" if n >= 100 else "~"
            print(f"  {status}  {d.name}:  {n:>4} samples")
            total += n
            per_class[d.name] = n
        else:
            print(f"  ✗  {d.name}:  0 samples")

    existing = {d.name for d in SAVE_DIR.iterdir() if d.is_dir()}
    missing = sorted(set(string.ascii_uppercase) - DYNAMIC_LETTERS - existing)

    print(f"\n  Total: {total} samples")
    if per_class:
        print(f"  Min:   {min(per_class.values())} ({min(per_class, key=per_class.get)})")
        print(f"  Max:   {max(per_class.values())} ({max(per_class, key=per_class.get)})")
    if missing:
        print(f"  Belum diproses: {', '.join(missing)}")

    # Check output files
    print(f"\n📦  Output files:")
    for fname in ["sibi_alphabet_model.tflite", "sibi_alphabet_model_f32.tflite",
                   "sibi_alphabet_labels.json", "sibi_alphabet_model.keras"]:
        fpath = WORKING_DIR / fname
        if fpath.exists():
            size = fpath.stat().st_size
            unit = "KB" if size < 1_000_000 else "MB"
            val = size / 1024 if unit == "KB" else size / (1024 * 1024)
            print(f"  ✓  {fname} ({val:.1f} {unit})")
        else:
            print(f"  ✗  {fname}")
    print()


# ═══════════════════════════════════════════════════════════════════════════════
#  MAIN
# ═══════════════════════════════════════════════════════════════════════════════

def main():
    parser = argparse.ArgumentParser(
        description="SIBI Alphabet: Extract landmarks + Train Dense classifier (Kaggle)",
        epilog="""
Commands:
  extract   — Ekstrak MediaPipe landmarks dari gambar SIBI
  train     — Train Dense classifier → export TFLite
  stats     — Tampilkan ringkasan dataset & output
  all       — Extract + Train (full pipeline)

Paths (Kaggle):
  Input:    /kaggle/input/sibi-dataset/SIBI/
  Output:   /kaggle/working/
        """,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("command", choices=["extract", "train", "stats", "all"],
                        help="Command to run")
    parser.add_argument("--letters", nargs="+", help="Huruf tertentu saja (untuk extract)")
    parser.add_argument("--epochs", type=int, default=100, help="Jumlah epochs (default: 100)")
    parser.add_argument("--batch-size", type=int, default=64, help="Batch size (default: 64)")

    args = parser.parse_args()

    if args.command == "extract":
        extract_all(args.letters)
    elif args.command == "train":
        train_model(epochs=args.epochs, batch_size=args.batch_size)
    elif args.command == "stats":
        print_stats()
    elif args.command == "all":
        extract_all(args.letters)
        train_model(epochs=args.epochs, batch_size=args.batch_size)
        print_stats()


if __name__ == "__main__":
    main()
