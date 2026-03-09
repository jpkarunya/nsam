"""
ML Model Training Pipeline
============================
Trains all ML models on a synthetic but realistic dataset.
Run this script BEFORE starting the FastAPI server.

Synthetic dataset generation:
  - Class 0 (Normal):     Typical web browsing, DNS, HTTP traffic
  - Class 1 (Suspicious): Port scans, unusual ports, medium frequency
  - Class 2 (Malicious):  DoS patterns, brute-force, exfiltration signatures

In production, replace with real labeled datasets such as:
  - CICIDS 2017/2018 (Canadian Institute for Cybersecurity)
  - NSL-KDD
  - UNSW-NB15
"""

import sys
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

import numpy as np
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report, confusion_matrix
from loguru import logger

from ml.preprocessor import FeatureEngineer, FEATURE_COLS, NUM_FEATURES
from ml.threat_classifier import ThreatClassifier
from ml.anomaly_detector import AnomalyDetector

# Create models directory
MODELS_DIR = Path(__file__).parent.parent / "models"
MODELS_DIR.mkdir(exist_ok=True)

SCALER_PATH = MODELS_DIR / "scaler.joblib"


# ===========================================================================
# Synthetic Dataset Generator
# ===========================================================================

def generate_synthetic_dataset(n_samples: int = 10_000, seed: int = 42) -> tuple:
    """
    Generate a synthetic network traffic dataset with realistic feature distributions.

    Returns:
        X: np.ndarray (n_samples, NUM_FEATURES)
        y: np.ndarray (n_samples,) with labels 0/1/2
    """
    rng = np.random.default_rng(seed)
    rows = []
    labels = []

    n_normal = int(n_samples * 0.70)     # 70% normal (realistic imbalance)
    n_suspicious = int(n_samples * 0.20)  # 20% suspicious
    n_malicious = n_samples - n_normal - n_suspicious  # 10% malicious

    logger.info(f"Generating dataset: {n_normal} normal, "
                f"{n_suspicious} suspicious, {n_malicious} malicious")

    # -----------------------------------------------------------------------
    # Class 0: Normal traffic
    # -----------------------------------------------------------------------
    for _ in range(n_normal):
        protocol = rng.choice(["TCP", "UDP", "ICMP", "OTHER"], p=[0.6, 0.3, 0.05, 0.05])
        pkt_len = int(np.clip(rng.normal(800, 400), 64, 1500))
        ttl = int(rng.choice([64, 128, 255]))
        src_port = int(rng.integers(1024, 65535))
        dst_port = int(rng.choice([80, 443, 53, 8080, 22], p=[0.35, 0.35, 0.2, 0.05, 0.05]))
        conn_freq = int(rng.integers(1, 30))
        flow_dur = float(rng.uniform(0.1, 60))
        rows.append(_make_row(protocol, pkt_len, ttl, src_port, dst_port, conn_freq, flow_dur))
        labels.append(0)

    # -----------------------------------------------------------------------
    # Class 1: Suspicious traffic
    # -----------------------------------------------------------------------
    for _ in range(n_suspicious):
        protocol = rng.choice(["TCP", "UDP"], p=[0.7, 0.3])
        pkt_len = int(np.clip(rng.normal(200, 100), 40, 1000))  # smaller probes
        ttl = int(rng.integers(30, 128))
        src_port = int(rng.integers(1024, 65535))
        # Suspicious: unusual destination ports
        dst_port = int(rng.choice([21, 22, 23, 25, 3306, 3389, 5900, 6379, 8888]))
        conn_freq = int(rng.integers(50, 200))    # elevated frequency
        flow_dur = float(rng.uniform(0.001, 5))   # short flows
        rows.append(_make_row(protocol, pkt_len, ttl, src_port, dst_port, conn_freq, flow_dur))
        labels.append(1)

    # -----------------------------------------------------------------------
    # Class 2: Malicious traffic
    # -----------------------------------------------------------------------
    for _ in range(n_malicious):
        attack_type = rng.choice(["dos", "scan", "exfil", "bruteforce"])

        if attack_type == "dos":
            protocol = "UDP"
            pkt_len = int(np.clip(rng.normal(1400, 100), 1000, 1500))  # max-size UDP floods
            conn_freq = int(rng.integers(500, 5000))
            flow_dur = float(rng.uniform(0.001, 2))
            dst_port = int(rng.integers(1, 1024))
            ttl = 64

        elif attack_type == "scan":
            protocol = "TCP"
            pkt_len = int(np.clip(rng.normal(60, 20), 40, 120))  # tiny SYN probes
            conn_freq = int(rng.integers(200, 1000))
            flow_dur = float(rng.uniform(0.001, 0.1))
            dst_port = int(rng.integers(1, 65535))  # random port scan
            ttl = int(rng.integers(30, 64))

        elif attack_type == "exfil":
            protocol = "TCP"
            pkt_len = int(np.clip(rng.normal(1400, 50), 1200, 1500))  # large data
            conn_freq = int(rng.integers(100, 500))
            flow_dur = float(rng.uniform(60, 3600))  # long flows
            dst_port = int(rng.choice([443, 80, 4444, 8443]))
            ttl = 128

        else:  # bruteforce
            protocol = "TCP"
            pkt_len = int(np.clip(rng.normal(200, 50), 100, 400))
            conn_freq = int(rng.integers(300, 2000))
            flow_dur = float(rng.uniform(0.01, 1))
            dst_port = int(rng.choice([22, 23, 3389, 5900]))
            ttl = int(rng.choice([64, 128]))

        src_port = int(rng.integers(1024, 65535))
        rows.append(_make_row(protocol, pkt_len, ttl, src_port, dst_port, conn_freq, flow_dur))
        labels.append(2)

    df = pd.DataFrame(rows, columns=FEATURE_COLS)
    y = np.array(labels)

    # Shuffle
    idx = rng.permutation(len(df))
    return df.iloc[idx].reset_index(drop=True), y[idx]


def _make_row(protocol, pkt_len, ttl, src_port, dst_port, conn_freq, flow_dur) -> list:
    """Build one feature row matching FEATURE_COLS order."""
    # RAW_NUMERIC_COLS: packet_length, ttl, src_port, dst_port, conn_frequency, flow_duration
    numeric = [pkt_len, ttl, src_port, dst_port, conn_freq, flow_dur]

    # PROTOCOL_COLS: proto_TCP, proto_UDP, proto_ICMP
    protos = [int(protocol == "TCP"), int(protocol == "UDP"), int(protocol == "ICMP")]

    # FLAG_COLS: flag_SYN, flag_ACK, flag_FIN, flag_RST, flag_PSH, flag_URG
    # For synthetic data, assign flags based on protocol
    import random
    if protocol == "TCP":
        flags = [random.randint(0, 1) for _ in range(6)]
    else:
        flags = [0] * 6

    # IP_FEATURE_COLS: src_ip_private, dst_ip_private, src_dst_same_subnet
    ip_features = [random.randint(0, 1), random.randint(0, 1), random.randint(0, 1)]

    return numeric + protos + flags + ip_features


# ===========================================================================
# Training Pipeline
# ===========================================================================

def train_all_models():
    logger.info("=" * 60)
    logger.info("NetGuard ML Training Pipeline")
    logger.info("=" * 60)

    # --- Generate dataset ---
    feature_df, y = generate_synthetic_dataset(n_samples=15_000)
    logger.info(f"Dataset shape: {feature_df.shape} | Label distribution: "
                f"{dict(zip(*np.unique(y, return_counts=True)))}")

    # --- Feature engineer: fit scaler ---
    fe = FeatureEngineer()
    X = fe.fit_transform(feature_df)
    fe.save_scaler(str(SCALER_PATH))
    logger.info(f"Scaler fitted and saved → {SCALER_PATH}")

    # --- Train/test split ---
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )

    # --- Module 4: Train XGBoost Classifier ---
    logger.info("\n--- Training XGBoost Classifier ---")
    classifier = ThreatClassifier()
    classifier.fit(
        X_train, y_train,
        eval_set=[(X_test, y_test)],
        early_stopping_rounds=20,
    )
    preds = classifier.predict(X_test)
    pred_labels = [p.label_id for p in preds]
    logger.info("\nClassification Report:\n" +
                classification_report(y_test, pred_labels,
                                      target_names=["Normal", "Suspicious", "Malicious"]))
    classifier.save()

    # --- Module 5: Train K-Means Anomaly Detector on normal traffic only ---
    logger.info("\n--- Training K-Means Anomaly Detector ---")
    normal_mask = y_train == 0
    X_normal = X_train[normal_mask]
    logger.info(f"Training K-Means on {len(X_normal)} normal samples")

    detector = AnomalyDetector(n_clusters=8, threshold=0.75)
    detector.fit(X_normal)
    detector.save()

    # Evaluate anomaly detection on test set
    all_anomalies = detector.predict(X_test)
    anomaly_scores = [a.anomaly_score for a in all_anomalies]
    is_anomaly = [a.is_anomaly for a in all_anomalies]

    # Malicious traffic should have higher anomaly scores
    mal_mask = y_test == 2
    norm_mask = y_test == 0
    mal_scores = np.array(anomaly_scores)[mal_mask]
    norm_scores = np.array(anomaly_scores)[norm_mask]

    logger.info(f"Anomaly scores — Normal: mean={norm_scores.mean():.3f} "
                f"| Malicious: mean={mal_scores.mean():.3f}")

    logger.info("\n" + "=" * 60)
    logger.info("Training complete! Models saved to /models/")
    logger.info("  - models/xgb_classifier.joblib")
    logger.info("  - models/kmeans_anomaly.joblib")
    logger.info("  - models/scaler.joblib")
    logger.info("=" * 60)


if __name__ == "__main__":
    train_all_models()

