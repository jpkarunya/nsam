"""
MODULE 2 — Data Preprocessing Engine
MODULE 3 — Feature Engineering
========================================
Transforms raw PacketRecord objects into a clean, normalized NumPy/Pandas
feature matrix suitable for the ML models.

Pipeline steps:
  1. Validate and coerce types
  2. Encode categorical features (protocol → one-hot, flags → binary)
  3. Clip outliers (IQR-based) on numerical columns
  4. StandardScaler normalization
  5. Return a (DataFrame, numpy array) tuple
"""

import re
import ipaddress
import numpy as np
import pandas as pd
from sklearn.preprocessing import StandardScaler
from typing import Union
from loguru import logger

from .packet_capture import PacketRecord


# ---------------------------------------------------------------------------
# Feature column definitions
# ---------------------------------------------------------------------------

# Raw numeric columns extracted directly from PacketRecord
RAW_NUMERIC_COLS = [
    "packet_length",
    "ttl",
    "src_port",
    "dst_port",
    "conn_frequency",
    "flow_duration",
]

# Protocol one-hot columns (TCP, UDP, ICMP; OTHER → all zeros)
PROTOCOL_COLS = ["proto_TCP", "proto_UDP", "proto_ICMP"]

# TCP flag presence indicators
FLAG_COLS = ["flag_SYN", "flag_ACK", "flag_FIN", "flag_RST", "flag_PSH", "flag_URG"]

# IP-derived features
IP_FEATURE_COLS = [
    "src_ip_private",     # 1 if source IP is RFC-1918 private
    "dst_ip_private",     # 1 if destination IP is RFC-1918 private
    "src_dst_same_subnet",# 1 if same /24 subnet
]

# Final ordered feature list fed to ML models
FEATURE_COLS = RAW_NUMERIC_COLS + PROTOCOL_COLS + FLAG_COLS + IP_FEATURE_COLS
NUM_FEATURES = len(FEATURE_COLS)  # = 20


# ---------------------------------------------------------------------------
# IP helper utilities
# ---------------------------------------------------------------------------

def _is_private(ip_str: str) -> int:
    """Return 1 if IP is a private/loopback/link-local address, else 0."""
    try:
        addr = ipaddress.ip_address(ip_str)
        return int(addr.is_private or addr.is_loopback or addr.is_link_local)
    except ValueError:
        return 0


def _same_slash24(ip_a: str, ip_b: str) -> int:
    """Return 1 if both IPs share the same /24 subnet."""
    try:
        net_a = ipaddress.ip_network(ip_a + "/24", strict=False)
        net_b = ipaddress.ip_network(ip_b + "/24", strict=False)
        return int(net_a == net_b)
    except ValueError:
        return 0


# ---------------------------------------------------------------------------
# MODULE 2: Preprocessor
# ---------------------------------------------------------------------------

class DataPreprocessor:
    """
    Cleans and prepares packet records for feature engineering.

    Cleaning steps:
      - Replace NaN / None / invalid values with safe defaults
      - Clip extreme outliers to prevent model distortion
      - Validate IP address strings
    """

    # Clipping bounds per column (values outside are clamped)
    CLIP_BOUNDS: dict[str, tuple[float, float]] = {
        "packet_length": (20, 65535),
        "ttl": (1, 255),
        "src_port": (0, 65535),
        "dst_port": (0, 65535),
        "conn_frequency": (0, 10_000),
        "flow_duration": (0, 86400),  # max 1 day
    }

    def clean(self, records: list[PacketRecord]) -> pd.DataFrame:
        """
        Convert a list of PacketRecord objects to a clean DataFrame.
        Each row = one packet.
        """
        if not records:
            return pd.DataFrame(columns=["timestamp", "src_ip", "dst_ip",
                                          "protocol", "flags"] + RAW_NUMERIC_COLS)

        rows = [r.to_dict() for r in records]
        df = pd.DataFrame(rows)

        # --- Fill missing values with safe defaults ---
        df["protocol"] = df["protocol"].fillna("OTHER").str.upper()
        df["flags"] = df["flags"].fillna("")
        df["src_ip"] = df["src_ip"].fillna("0.0.0.0")
        df["dst_ip"] = df["dst_ip"].fillna("0.0.0.0")

        for col in RAW_NUMERIC_COLS:
            df[col] = pd.to_numeric(df[col], errors="coerce").fillna(0)

        # --- Clip outliers ---
        for col, (lo, hi) in self.CLIP_BOUNDS.items():
            if col in df.columns:
                df[col] = df[col].clip(lower=lo, upper=hi)

        logger.debug(f"Preprocessed {len(df)} records")
        return df


# ---------------------------------------------------------------------------
# MODULE 3: Feature Engineer
# ---------------------------------------------------------------------------

class FeatureEngineer:
    """
    Transforms a clean DataFrame into the final ML feature matrix.

    Outputs:
      - feature_df : pd.DataFrame with columns = FEATURE_COLS
      - X          : np.ndarray of shape (n_samples, NUM_FEATURES)
    """

    def __init__(self):
        self._scaler = StandardScaler()
        self._scaler_fitted = False

    def build_features(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Extract all features from a cleaned packet DataFrame.
        Returns a DataFrame with exactly FEATURE_COLS columns.
        """
        feat = pd.DataFrame(index=df.index)

        # --- Numeric pass-through ---
        for col in RAW_NUMERIC_COLS:
            feat[col] = df[col].astype(float)

        # --- Protocol one-hot ---
        for proto in ["TCP", "UDP", "ICMP"]:
            feat[f"proto_{proto}"] = (df["protocol"] == proto).astype(int)

        # --- TCP flag binary indicators ---
        flag_map = {"SYN": "S", "ACK": "A", "FIN": "F",
                    "RST": "R", "PSH": "P", "URG": "U"}
        for name, char in flag_map.items():
            feat[f"flag_{name}"] = df["flags"].str.contains(char, na=False).astype(int)

        # --- IP-derived features ---
        feat["src_ip_private"] = df["src_ip"].map(_is_private)
        feat["dst_ip_private"] = df["dst_ip"].map(_is_private)
        feat["src_dst_same_subnet"] = df.apply(
            lambda row: _same_slash24(row["src_ip"], row["dst_ip"]), axis=1
        )

        # Enforce column order
        feat = feat[FEATURE_COLS]
        return feat

    def fit_scaler(self, feature_df: pd.DataFrame) -> None:
        """Fit the StandardScaler on training data."""
        self._scaler.fit(feature_df.values)
        self._scaler_fitted = True
        logger.info("FeatureEngineer scaler fitted")

    def transform(self, feature_df: pd.DataFrame) -> np.ndarray:
        """
        Scale features. If scaler not yet fitted, do a simple min-max
        fallback so the system can still run without training.
        """
        X = feature_df.values.astype(float)
        if self._scaler_fitted:
            return self._scaler.transform(X)
        else:
            # Fallback: per-column min-max to [0, 1]
            col_min = X.min(axis=0)
            col_max = X.max(axis=0)
            rng = np.where(col_max - col_min == 0, 1, col_max - col_min)
            return (X - col_min) / rng

    def fit_transform(self, feature_df: pd.DataFrame) -> np.ndarray:
        """Convenience: fit then transform."""
        X = feature_df.values.astype(float)
        self._scaler.fit(X)
        self._scaler_fitted = True
        return self._scaler.transform(X)

    def save_scaler(self, path: str) -> None:
        import joblib
        joblib.dump(self._scaler, path)
        logger.info(f"Scaler saved → {path}")

    def load_scaler(self, path: str) -> None:
        import joblib
        self._scaler = joblib.load(path)
        self._scaler_fitted = True
        logger.info(f"Scaler loaded ← {path}")


# ---------------------------------------------------------------------------
# Convenience pipeline function
# ---------------------------------------------------------------------------

def preprocess_and_engineer(
    records: list[PacketRecord],
    feature_engineer: FeatureEngineer,
) -> tuple[pd.DataFrame, np.ndarray]:
    """
    Full pipeline: raw records → (feature_df, scaled X).
    Used inside detection routes.
    """
    preprocessor = DataPreprocessor()
    clean_df = preprocessor.clean(records)
    feature_df = feature_engineer.build_features(clean_df)
    X = feature_engineer.transform(feature_df)
    return feature_df, X
