#!/usr/bin/env python3
"""
prepare_bisindo_alphabet.py — Ekstrak Landmark + Train Model BISINDO Alphabet (Kaggle)
======================================================================================
Menggabungkan DUA dataset Kaggle untuk variasi angle & tangan yang lebih banyak
(palm view vs back-of-hand, posisi tangan berbeda, dsb):

  A. idhamozi/indonesian-sign-language-bisindo
       Dataset BISINDO/datatrain/{A..Z,NOTHING}/*.jpg       ← folder-per-class
       Dataset BISINDO/datatest/{A..Z,NOTHING}/*.jpg

  B. faizalfarizi/bisindo-hand-sign-detection-using-transferlearning
       Indonesian-Sign-Language-BISINDO-Hand-Sign/train/<LETTER>.<uuid>.jpg   ← flat,
       Indonesian-Sign-Language-BISINDO-Hand-Sign/test/<LETTER>.<uuid>.jpg      prefix=kelas
       (.xml Pascal-VOC bbox di-skip, MediaPipe lebih baik lihat full image)

Perbedaan dengan SIBI:
  - BISINDO pakai DUA TANGAN → detect 2 hands
  - 86 features: 2 × 21 landmarks × (x,y) + 2-dim relative offset antara pusat tangan
  - Flip augmentation + swap kiri↔kanan (bentuk huruf simetris)
  - Ada kelas NOTHING (tidak menunjukkan huruf)

Output:
  /kaggle/working/dataset_bisindo_alphabet/<HURUF>/landmarks.npy  shape=(N, 86)
  /kaggle/working/bisindo_alphabet_model_f32.tflite
  /kaggle/working/bisindo_alphabet_labels.json

Usage (Kaggle Notebook):
  # Cell 1: Extract landmarks
  !python prepare_bisindo_alphabet.py extract

  # Cell 2: Train model
  !python prepare_bisindo_alphabet.py train

  # Cell 3: Stats
  !python prepare_bisindo_alphabet.py stats

  # Atau semuanya sekaligus:
  !python prepare_bisindo_alphabet.py all
"""

import argparse
import json
import cv2
import mediapipe as mp
import numpy as np
from pathlib import Path

# ─── Kaggle paths ────────────────────────────────────────────────────────────
# Dua dataset digabung untuk variasi lebih banyak (palm vs back-of-hand, dll).
#
# Dataset A (idhamozi) — folder-per-class:
#   Dataset BISINDO/datatrain/{A,B,...,Z,NOTHING}/*.jpg
#   Dataset BISINDO/datatest/{A,B,...,Z,NOTHING}/*.jpg
#
# Dataset B (faizalfarizi) — flat, huruf dari prefix filename:
#   Indonesian-Sign-Language-BISINDO-Hand-Sign-Detection-Dataset-master/train/<LETTER>.<uuid>.jpg
#   Indonesian-Sign-Language-BISINDO-Hand-Sign-Detection-Dataset-master/test/<LETTER>.<uuid>.jpg
#   (ada juga .xml Pascal-VOC bbox — kita abaikan, MediaPipe lebih tepat pakai full image)
DATASET_A_ROOTS = [
    Path("/kaggle/input/datasets/idhamozi/indonesian-sign-language-bisindo/Dataset BISINDO/datatrain"),
    Path("/kaggle/input/datasets/idhamozi/indonesian-sign-language-bisindo/Dataset BISINDO/datatest"),
]
DATASET_B_ROOTS = [
    Path("/kaggle/input/datasets/faizalfarizi/bisindo-hand-sign-detection-using-transferlearning/Indonesian-Sign-Language-BISINDO-Hand-Sign-Detection-Dataset-master/train"),
    Path("/kaggle/input/datasets/faizalfarizi/bisindo-hand-sign-detection-using-transferlearning/Indonesian-Sign-Language-BISINDO-Hand-Sign-Detection-Dataset-master/test"),
]

WORKING_DIR = Path("/kaggle/working")
SAVE_DIR = WORKING_DIR / "dataset_bisindo_alphabet"

# ─── Constants ───────────────────────────────────────────────────────────────
# 21 landmarks × 2 (x, y) × 2 hands + 2 (relative offset between hand centers)
NUM_LANDMARKS = 21
NUM_FEATURES_PER_HAND = NUM_LANDMARKS * 2   # 42
NUM_FEATURES = NUM_FEATURES_PER_HAND * 2 + 2  # 86

# Kelas yang diharapkan (A-Z + NOTHING = 27 kelas)
EXPECTED_CLASSES = sorted([
    "A", "B", "C", "D", "E", "F", "G", "H", "I", "J",
    "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T",
    "U", "V", "W", "X", "Y", "Z", "NOTHING",
])

mp_hands = mp.solutions.hands


# ═══════════════════════════════════════════════════════════════════════════════
#  NORMALIZATION
# ═══════════════════════════════════════════════════════════════════════════════

def normalize_hand(coords: np.ndarray) -> np.ndarray:
    """Boháček bbox-normalization: (21, 2) → 42 floats in [0, 1]."""
    min_xy = coords.min(axis=0)
    max_xy = coords.max(axis=0)
    span = max_xy - min_xy
    span = np.maximum(span, 1e-6)  # avoid div-by-zero
    norm = (coords - min_xy) / span
    return norm.flatten()  # 42


def make_features(hand_left: np.ndarray, hand_right: np.ndarray) -> np.ndarray:
    """Combine two hands into 86-dim feature vector.

    Args:
        hand_left:  (21, 2) raw landmark coords for left hand
        hand_right: (21, 2) raw landmark coords for right hand

    Returns:
        86 floats: [left_42, right_42, dx_center, dy_center]
    """
    # Normalize each hand independently
    left_norm = normalize_hand(hand_left)    # 42
    right_norm = normalize_hand(hand_right)  # 42

    # Relative offset between hand centers (in raw coords)
    center_l = hand_left.mean(axis=0)
    center_r = hand_right.mean(axis=0)
    offset = center_r - center_l  # (dx, dy) — captures spatial relationship

    return np.concatenate([left_norm, right_norm, offset]).astype(np.float32)


def make_features_single_hand(hand: np.ndarray) -> np.ndarray:
    """Create 86-dim feature from a single hand (zero-pad the other slot).

    Banyak gambar BISINDO alphabet dua tangan saling tumpuk, sehingga
    MediaPipe hanya detect 1 tangan. Daripada buang data, kita isi slot
    tangan kedua dengan zeros + offset nol.

    Args:
        hand: (21, 2) raw landmark coords of the detected hand

    Returns:
        86 floats: [hand_42, zeros_42, 0.0, 0.0]
    """
    hand_norm = normalize_hand(hand)  # 42
    zeros = np.zeros(42, dtype=np.float32)
    offset = np.zeros(2, dtype=np.float32)
    return np.concatenate([hand_norm, zeros, offset]).astype(np.float32)


def extract_hands(landmarks_list, handedness_list):
    """Parse MediaPipe results into hand coords.

    Returns:
        ('two', left, right) if both hands detected
        ('one', hand_coords)  if only one hand detected
        None if no hands
    """
    if not landmarks_list:
        return None

    left = None
    right = None

    for lm, hand in zip(landmarks_list, handedness_list):
        coords = np.array([[l.x, l.y] for l in lm.landmark], dtype=np.float32)
        label = hand.classification[0].label  # "Left" or "Right"
        if label == "Left" and left is None:
            left = coords
        elif label == "Right" and right is None:
            right = coords

    if left is not None and right is not None:
        return ('two', left, right)
    elif left is not None:
        return ('one', left)
    elif right is not None:
        return ('one', right)
    else:
        # Fallback: ambil tangan pertama (handedness bisa salah)
        coords = np.array(
            [[l.x, l.y] for l in landmarks_list[0].landmark],
            dtype=np.float32,
        )
        return ('one', coords)


# ═══════════════════════════════════════════════════════════════════════════════
#  AUGMENTATION
# ═══════════════════════════════════════════════════════════════════════════════

def _flip_hand(coords: np.ndarray) -> np.ndarray:
    """Flip horizontal: mirror x coords."""
    flipped = coords.copy()
    flipped[:, 0] = 1.0 - flipped[:, 0]
    return flipped


def augment_two_hands(left: np.ndarray, right: np.ndarray) -> list[np.ndarray]:
    """Generate augmented 86-dim feature vectors from a two-hand pair.

    Augmentasi dilakukan pada koordinat RAW (sebelum Boháček normalization).
    Termasuk flip horizontal — bentuk huruf BISINDO simetris, jadi mirror
    + swap kiri↔kanan menghasilkan variasi yang valid.

    Returns ~39 feature vectors per sample.
    """
    results = []

    # --- 0. Original ---
    results.append(make_features(left, right))

    # --- 1. Flip horizontal: mirror kedua tangan + swap left↔right ---
    fl = _flip_hand(left)
    fr = _flip_hand(right)
    results.append(make_features(fr, fl))  # swap: flipped-right jadi left

    # --- 2. Rotasi: ±5°, ±10°, ±15°, ±20°, ±25° (putar kedua tangan bersama) ---
    all_pts = np.concatenate([left, right], axis=0)  # (42, 2)
    cx, cy = all_pts[:, 0].mean(), all_pts[:, 1].mean()

    for angle_deg in [-25, -20, -15, -10, -5, 5, 10, 15, 20, 25]:
        rad = np.radians(angle_deg)
        cos_a, sin_a = np.cos(rad), np.sin(rad)

        def rotate(coords, _cos=cos_a, _sin=sin_a):
            r = coords.copy()
            dx = r[:, 0] - cx
            dy = r[:, 1] - cy
            r[:, 0] = dx * _cos - dy * _sin + cx
            r[:, 1] = dx * _sin + dy * _cos + cy
            return r

        results.append(make_features(rotate(left), rotate(right)))

    # --- 3. Rotasi + flip (10 rotasi × flip) ---
    for angle_deg in [-25, -20, -15, -10, -5, 5, 10, 15, 20, 25]:
        rad = np.radians(angle_deg)
        cos_a, sin_a = np.cos(rad), np.sin(rad)

        def rotate_flip(coords, _cos=cos_a, _sin=sin_a):
            r = coords.copy()
            dx = r[:, 0] - cx
            dy = r[:, 1] - cy
            r[:, 0] = dx * _cos - dy * _sin + cx
            r[:, 1] = dx * _sin + dy * _cos + cy
            r[:, 0] = 1.0 - r[:, 0]  # flip
            return r

        rl = rotate_flip(left)
        rr = rotate_flip(right)
        results.append(make_features(rr, rl))  # swap after flip

    # --- 4. Scale jitter: ±5%, ±10%, ±15%, ±20% ---
    for scale in [0.80, 0.85, 0.90, 0.95, 1.05, 1.10, 1.15, 1.20]:
        def scale_fn(coords, s=scale):
            sc = coords.copy()
            sc[:, 0] = (sc[:, 0] - cx) * s + cx
            sc[:, 1] = (sc[:, 1] - cy) * s + cy
            return sc

        results.append(make_features(scale_fn(left), scale_fn(right)))

    # --- 5. Translate jitter: geser kecil (kedua tangan bersama) ---
    for dx, dy in [(-0.03, 0), (0.03, 0), (0, -0.03), (0, 0.03)]:
        l_shifted = left.copy()
        l_shifted[:, 0] += dx
        l_shifted[:, 1] += dy
        r_shifted = right.copy()
        r_shifted[:, 0] += dx
        r_shifted[:, 1] += dy
        results.append(make_features(l_shifted, r_shifted))

    # --- 6. Noise: Gaussian kecil + medium ---
    rng = np.random.default_rng()
    for std in [0.003, 0.005, 0.008, 0.010]:
        for _ in range(2):
            l_noisy = left + rng.normal(0, std, left.shape).astype(np.float32)
            r_noisy = right + rng.normal(0, std, right.shape).astype(np.float32)
            results.append(make_features(l_noisy, r_noisy))

    # --- 7. Relative hand distance jitter: geser satu tangan sedikit ---
    for dx, dy in [(0.02, 0), (-0.02, 0), (0, 0.02), (0, -0.02),
                   (0.04, 0), (-0.04, 0), (0, 0.04), (0, -0.04)]:
        r_shifted = right.copy()
        r_shifted[:, 0] += dx
        r_shifted[:, 1] += dy
        results.append(make_features(left, r_shifted))

    return results  # total: 1 + 1 + 10 + 10 + 8 + 4 + 8 + 8 ≈ 50 per sample


def augment_single_hand(hand: np.ndarray) -> list[np.ndarray]:
    """Augmentasi untuk kasus 1 tangan terdeteksi.

    Lebih sedikit variasi (tidak ada hand-distance jitter, tidak ada swap).
    Returns ~17 feature vectors.
    """
    results = []

    # --- 0. Original ---
    results.append(make_features_single_hand(hand))

    # --- 1. Flip horizontal ---
    flipped = _flip_hand(hand)
    results.append(make_features_single_hand(flipped))

    # --- 2. Rotasi (lebih banyak) ---
    cx, cy = hand[:, 0].mean(), hand[:, 1].mean()
    for angle_deg in [-25, -20, -15, -10, -5, 5, 10, 15, 20, 25]:
        rad = np.radians(angle_deg)
        cos_a, sin_a = np.cos(rad), np.sin(rad)
        r = hand.copy()
        dx = r[:, 0] - cx
        dy = r[:, 1] - cy
        r[:, 0] = dx * cos_a - dy * sin_a + cx
        r[:, 1] = dx * sin_a + dy * cos_a + cy
        results.append(make_features_single_hand(r))

    # --- 3. Scale jitter ---
    for scale in [0.80, 0.85, 0.90, 0.95, 1.05, 1.10, 1.15, 1.20]:
        sc = hand.copy()
        sc[:, 0] = (sc[:, 0] - cx) * scale + cx
        sc[:, 1] = (sc[:, 1] - cy) * scale + cy
        results.append(make_features_single_hand(sc))

    # --- 4. Noise ---
    rng = np.random.default_rng()
    for std in [0.003, 0.005, 0.008, 0.010]:
        for _ in range(2):
            noisy = hand + rng.normal(0, std, hand.shape).astype(np.float32)
            results.append(make_features_single_hand(noisy))

    return results  # total: 1 + 1 + 10 + 8 + 8 ≈ 28 per sample


# ═══════════════════════════════════════════════════════════════════════════════
#  STEP 1: EXTRACT LANDMARKS
# ═══════════════════════════════════════════════════════════════════════════════

IMG_EXTS = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}


def _collect_images_dataset_a(root: Path) -> dict[str, list[Path]]:
    """Dataset A (idhamozi): folder-per-class → {LETTER: [img_paths]}."""
    out: dict[str, list[Path]] = {}
    if not root.exists():
        return out
    for sub in sorted(root.iterdir()):
        if not sub.is_dir():
            continue
        letter = sub.name.upper()
        imgs = sorted(f for f in sub.iterdir() if f.suffix.lower() in IMG_EXTS)
        if imgs:
            out.setdefault(letter, []).extend(imgs)
    return out


def _collect_images_dataset_b(root: Path) -> dict[str, list[Path]]:
    """Dataset B (faizalfarizi): flat, prefix nama file = kelas.

    Filename pattern: `<LETTER>.<uuid>.jpg` → ambil karakter pertama sebagai kelas.
    Case-insensitive. Skip file yang prefix-nya bukan A-Z atau 'NOTHING'.
    """
    out: dict[str, list[Path]] = {}
    if not root.exists():
        return out
    for f in sorted(root.iterdir()):
        if f.suffix.lower() not in IMG_EXTS:
            continue
        stem = f.stem  # misal "A.275ba73c-e263-..."
        # Ambil token pertama sebelum '.' atau '_'
        head = stem.split(".")[0].split("_")[0].upper()
        if head == "NOTHING" or (len(head) == 1 and "A" <= head <= "Z"):
            out.setdefault(head, []).append(f)
    return out


def _process_images(letter: str, images: list[Path], hands) -> list[np.ndarray]:
    """Ekstrak landmarks + augmentasi dari list gambar untuk satu kelas.

    Return list of 86-dim feature vectors.
    """
    samples: list[np.ndarray] = []
    detected_2h = 0
    detected_1h = 0
    skipped = 0

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

        if result.multi_hand_landmarks and result.multi_handedness:
            parsed = extract_hands(
                result.multi_hand_landmarks,
                result.multi_handedness,
            )
            if parsed is not None and parsed[0] == 'two':
                _, left, right = parsed
                samples.extend(augment_two_hands(left, right))
                detected_2h += 1
            elif parsed is not None and parsed[0] == 'one':
                samples.extend(augment_single_hand(parsed[1]))
                detected_1h += 1
            else:
                skipped += 1
        elif letter == "NOTHING":
            feats = np.zeros(NUM_FEATURES, dtype=np.float32)
            samples.append(feats)
            rng = np.random.default_rng()
            for _ in range(4):
                noisy = rng.normal(0, 0.01, NUM_FEATURES).astype(np.float32)
                samples.append(noisy)
        else:
            skipped += 1

    print(f"    {letter:>8s}:  2h={detected_2h:<4} 1h={detected_1h:<4} skip={skipped:<4} "
          f"→ {len(samples):>5} features")
    return samples


def extract_all(letters: list[str] | None = None):
    """Ekstrak landmarks dari kedua dataset (A + B) dan gabungkan per kelas."""
    # ── Kumpulkan semua path gambar per kelas, dari semua root dataset ──────
    combined: dict[str, list[Path]] = {}

    print(f"\n📂  Dataset A (idhamozi):")
    for root in DATASET_A_ROOTS:
        d = _collect_images_dataset_a(root)
        if d:
            total = sum(len(v) for v in d.values())
            print(f"    ✓ {root} — {len(d)} kelas, {total} gambar")
            for k, v in d.items():
                combined.setdefault(k, []).extend(v)
        else:
            print(f"    ✗ {root} — (tidak ditemukan / kosong)")

    print(f"\n📂  Dataset B (faizalfarizi):")
    for root in DATASET_B_ROOTS:
        d = _collect_images_dataset_b(root)
        if d:
            total = sum(len(v) for v in d.values())
            print(f"    ✓ {root} — {len(d)} kelas, {total} gambar")
            for k, v in d.items():
                combined.setdefault(k, []).extend(v)
        else:
            print(f"    ✗ {root} — (tidak ditemukan / kosong)")

    if not combined:
        print("\n❌ Tidak ada gambar ditemukan di kedua dataset. Periksa path!")
        return 0

    # Filter by letters list if provided
    if letters is None:
        letters_sorted = sorted(combined.keys())
    else:
        letters_sorted = sorted(l.upper() for l in letters if l.upper() in combined)

    print(f"\n🔤  Akan memproses {len(letters_sorted)} kelas: {letters_sorted}")
    print(f"💾  Output:  {SAVE_DIR}\n")

    # ── Proses per kelas ────────────────────────────────────────────────────
    SAVE_DIR.mkdir(parents=True, exist_ok=True)
    total = 0
    per_class_summary: dict[str, int] = {}

    with mp_hands.Hands(
        static_image_mode=True,
        max_num_hands=2,
        min_detection_confidence=0.3,
    ) as hands:
        print("── extraction ─────────────────────────────────────")
        for letter in letters_sorted:
            imgs = combined.get(letter, [])
            if not imgs:
                print(f"    {letter:>8s}:  (kosong, dilewati)")
                continue
            print(f"  [{letter}] {len(imgs)} gambar dari gabungan dataset")
            samples = _process_images(letter, imgs, hands)
            if samples:
                save_dir = SAVE_DIR / letter
                save_dir.mkdir(parents=True, exist_ok=True)
                arr = np.array(samples, dtype=np.float32)
                np.save(save_dir / "landmarks.npy", arr)
                total += len(samples)
                per_class_summary[letter] = len(samples)

    print(f"\n{'─'*60}")
    print(f"  Total: {total} samples dari {len(per_class_summary)} kelas")
    if per_class_summary:
        mn = min(per_class_summary.values())
        mx = max(per_class_summary.values())
        print(f"  Min: {mn} ({min(per_class_summary, key=per_class_summary.get)})  "
              f"Max: {mx} ({max(per_class_summary, key=per_class_summary.get)})  "
              f"Ratio: {mx/max(mn,1):.1f}x")
    print(f"{'─'*60}\n")
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
        and not d.name.startswith("_")
    )

    if not labels:
        raise FileNotFoundError(
            f"Tidak ada data di {SAVE_DIR}. Jalankan 'extract' dulu!")

    label_to_idx = {lbl: i for i, lbl in enumerate(labels)}

    for lbl in labels:
        arr = np.load(SAVE_DIR / lbl / "landmarks.npy")
        X_all.append(arr)
        y_all.extend([label_to_idx[lbl]] * len(arr))

    X = np.concatenate(X_all, axis=0)  # (N_total, 86)
    y = np.array(y_all, dtype=np.int32)

    print(f"📊  Dataset: {len(X)} samples, {len(labels)} kelas, {X.shape[1]} features")
    print(f"    Labels: {labels}\n")

    return X, y, labels


def train_model(epochs: int = 150, batch_size: int = 128):
    """Train Dense classifier for BISINDO alphabet → export TFLite."""
    import tensorflow as tf
    from sklearn.model_selection import train_test_split

    X, y, labels = load_dataset()
    num_classes = len(labels)

    assert X.shape[1] == NUM_FEATURES, (
        f"Feature dimension mismatch: got {X.shape[1]}, expected {NUM_FEATURES}")

    # Split stratified
    X_train, X_val, y_train, y_val = train_test_split(
        X, y, test_size=0.15, random_state=42, stratify=y
    )
    print(f"🔀  Train: {len(X_train)}, Val: {len(X_val)}")

    # Check class balance
    unique, counts = np.unique(y_train, return_counts=True)
    min_count = counts.min()
    max_count = counts.max()
    print(f"    Class balance: min={min_count}, max={max_count}, "
          f"ratio={max_count/max(min_count,1):.1f}x\n")

    # Class weights untuk handle imbalance
    total_samples = len(y_train)
    class_weight = {}
    for c, cnt in zip(unique, counts):
        class_weight[int(c)] = total_samples / (num_classes * cnt)

    # Online augmentation: noise ringan tambahan saat training
    def augment(x):
        noise = tf.random.normal(shape=tf.shape(x), mean=0.0, stddev=0.01)
        return x + noise

    train_ds = tf.data.Dataset.from_tensor_slices((X_train, y_train))
    train_ds = train_ds.shuffle(len(X_train)).batch(batch_size)
    train_ds = train_ds.map(lambda x, y: (augment(x), y))
    train_ds = train_ds.prefetch(tf.data.AUTOTUNE)

    val_ds = tf.data.Dataset.from_tensor_slices((X_val, y_val))
    val_ds = val_ds.batch(batch_size).prefetch(tf.data.AUTOTUNE)

    # ─── Model: Dense classifier ──────────────────────────────────────────
    # 86 input features → deeper network untuk dua tangan
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
            monitor="val_accuracy", patience=20, restore_best_weights=True
        ),
        tf.keras.callbacks.ReduceLROnPlateau(
            monitor="val_loss", factor=0.5, patience=7, min_lr=1e-6
        ),
    ]

    # Train
    print(f"\n🚀  Training {epochs} epochs...\n")
    history = model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=epochs,
        callbacks=callbacks,
        class_weight=class_weight,
        verbose=1,
    )

    # Final eval
    val_loss, val_acc = model.evaluate(val_ds, verbose=0)
    print(f"\n✅  Val accuracy: {val_acc:.4f}")

    # ─── Per-class accuracy ──────────────────────────────────────────────
    y_pred = model.predict(X_val, verbose=0).argmax(axis=1)
    print(f"\n📊  Per-class accuracy:")
    for i, lbl in enumerate(labels):
        mask = y_val == i
        if mask.sum() == 0:
            continue
        acc = (y_pred[mask] == i).mean()
        print(f"    {lbl:>8s}: {acc:.3f} ({mask.sum()} samples)")

    # ─── Confusion matrix (top confusions) ────────────────────────────────
    from collections import Counter
    confusions = Counter()
    for true, pred in zip(y_val, y_pred):
        if true != pred:
            confusions[(labels[true], labels[pred])] += 1

    if confusions:
        print(f"\n⚠  Top confusions:")
        for (true_lbl, pred_lbl), count in confusions.most_common(10):
            print(f"    {true_lbl} → {pred_lbl}: {count}x")

    # ─── Export TFLite F32 ────────────────────────────────────────────────
    tflite_f32_path = WORKING_DIR / "bisindo_alphabet_model_f32.tflite"
    converter_f32 = tf.lite.TFLiteConverter.from_keras_model(model)
    tflite_f32 = converter_f32.convert()
    tflite_f32_path.write_bytes(tflite_f32)
    print(f"\n💾  TFLite F32:  {tflite_f32_path} ({len(tflite_f32)/1024:.1f} KB)")

    # ─── Export TFLite INT8 ───────────────────────────────────────────────
    tflite_path = WORKING_DIR / "bisindo_alphabet_model.tflite"
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]

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

    # ─── Export labels JSON ───────────────────────────────────────────────
    labels_path = WORKING_DIR / "bisindo_alphabet_labels.json"
    labels_path.write_text(json.dumps(labels, indent=2))
    print(f"🏷️  Labels: {labels_path}")

    # ─── Export Keras model ───────────────────────────────────────────────
    keras_path = WORKING_DIR / "bisindo_alphabet_model.keras"
    model.save(keras_path)
    print(f"📦  Keras:  {keras_path}")

    print(f"\n{'─'*55}")
    print(f"  🎉  Selesai! Copy file berikut ke Flutter assets:")
    print(f"       {tflite_f32_path.name}")
    print(f"       {labels_path.name}")
    print(f"{'─'*55}\n")

    return model, history


# ═══════════════════════════════════════════════════════════════════════════════
#  STATS
# ═══════════════════════════════════════════════════════════════════════════════

def print_stats():
    """Tampilkan ringkasan dataset BISINDO alphabet."""
    if not SAVE_DIR.exists():
        print("Dataset belum ada. Jalankan 'extract' dulu.")
        return

    print(f"\n📊  Dataset BISINDO Alphabet ({SAVE_DIR}/)\n")
    total = 0
    per_class = {}
    for d in sorted(SAVE_DIR.iterdir()):
        if not d.is_dir() or d.name.startswith("_"):
            continue
        npy = d / "landmarks.npy"
        if npy.exists():
            arr = np.load(npy)
            n = len(arr)
            dims = arr.shape[1] if arr.ndim == 2 else "?"
            status = "✓" if n >= 100 else "~"
            print(f"  {status}  {d.name:>8s}:  {n:>6} samples  ({dims} features)")
            total += n
            per_class[d.name] = n
        else:
            print(f"  ✗  {d.name:>8s}:  0 samples")

    print(f"\n  Total: {total} samples, {len(per_class)} kelas")
    if per_class:
        print(f"  Min:   {min(per_class.values()):>6} ({min(per_class, key=per_class.get)})")
        print(f"  Max:   {max(per_class.values()):>6} ({max(per_class, key=per_class.get)})")
        avg = total / len(per_class)
        print(f"  Avg:   {avg:>6.0f}")

    # Check output files
    print(f"\n📦  Output files:")
    for fname in ["bisindo_alphabet_model_f32.tflite",
                   "bisindo_alphabet_model.tflite",
                   "bisindo_alphabet_labels.json",
                   "bisindo_alphabet_model.keras"]:
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
        description="BISINDO Alphabet: Extract two-hand landmarks + Train Dense classifier (Kaggle)",
        epilog="""
Commands:
  extract   — Ekstrak MediaPipe landmarks (2 tangan) dari gambar BISINDO
  train     — Train Dense classifier → export TFLite
  stats     — Tampilkan ringkasan dataset & output
  all       — Extract + Train (full pipeline)

Paths (Kaggle, DUA dataset digabung):
  A: /kaggle/input/datasets/idhamozi/indonesian-sign-language-bisindo/
       Dataset BISINDO/{datatrain,datatest}/<LETTER>/*.jpg
  B: /kaggle/input/datasets/faizalfarizi/bisindo-hand-sign-detection-using-transferlearning/
       Indonesian-Sign-Language-BISINDO-Hand-Sign/{train,test}/<LETTER>.<uuid>.jpg
  Output: /kaggle/working/

Features (86-dim):
  [left_hand_42] + [right_hand_42] + [offset_dx, offset_dy]
        """,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("command", choices=["extract", "train", "stats", "all"],
                        help="Command to run")
    parser.add_argument("--letters", nargs="+",
                        help="Kelas tertentu saja (untuk extract)")
    parser.add_argument("--epochs", type=int, default=150,
                        help="Jumlah epochs (default: 150)")
    parser.add_argument("--batch-size", type=int, default=128,
                        help="Batch size (default: 128)")

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
