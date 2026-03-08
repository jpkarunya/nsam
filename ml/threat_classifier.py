"""
MODULE 4 — XGBoost Threat Classification
==========================================
Classifies each network packet into one of three threat levels:
  0 = Normal
  1 = Suspicious
  2 = Malicious

Model: XGBClassifier (gradient-boosted decision trees)
  - Excellent for tabular security data
  - Handles class imbalance via scale_pos_weight
  - Outputs calibrated class probabilities

This module exposes:
  - ThreatClassifier.predict()   → list of ThreatResult
  - ThreatClassifier.save()      → persist model
  - ThreatClassifier.load()      → restore model
"""

from __future__ import annotations

import numpy as np
import joblib
from dataclasses import dataclass
from pathlib import Path
from typing import Optional
from xgboost import XGBClassifier
from loguru import logger


# ---------------------------------------------------------------------------
# Label constants
# ---------------------------------------------------------------------------

LABEL_MAP = {0: "Normal", 1: "Suspicious", 2: "Malicious"}
LABEL_COLORS = {0: "#00FF88", 1: "#FFB800", 2: "#FF3366"}


# ---------------------------------------------------------------------------
# Output data class
# ---------------------------------------------------------------------------

@dataclass
class ThreatResult:
    label: str                   # "Normal" | "Suspicious" | "Malicious"
    label_id: int                # 0 | 1 | 2
    prob_normal: float           # P(Normal)
    prob_suspicious: float       # P(Suspicious)
    prob_malicious: float        # P(Malicious)
    confidence: float            # max(probabilities)
    color: str                   # Hex color for dashboard


# ---------------------------------------------------------------------------
# Classifier wrapper
# ---------------------------------------------------------------------------

class ThreatClassifier:
    """
    XGBoost-based threat classification engine.

    Design decisions:
      - use_label_encoder=False silences deprecation warnings
      - eval_metric='mlogloss' for multiclass
      - n_estimators=200, max_depth=6: good balance of speed vs accuracy
      - class imbalance handled by sample_weight in fit()
    """

    DEFAULT_MODEL_PATH = Path(__file__).parent.parent / "models" / "xgb_classifier.joblib"

    def __init__(self):
        self._model: Optional[XGBClassifier] = None
        self._fitted = False

    def build_model(self) -> XGBClassifier:
        """Instantiate a fresh XGBClassifier with production hyperparameters."""
        return XGBClassifier(
            n_estimators=200,
            max_depth=6,
            learning_rate=0.05,
            subsample=0.8,
            colsample_bytree=0.8,
            use_label_encoder=False,
            eval_metric="mlogloss",
            objective="multi:softprob",
            num_class=3,
            tree_method="hist",     # faster on large datasets
            n_jobs=-1,
            random_state=42,
        )

    def fit(self, X: np.ndarray, y: np.ndarray,
            eval_set=None, early_stopping_rounds: int = 20) -> None:
        """
        Train the classifier.

        Args:
            X: Feature matrix (n_samples, n_features)
            y: Labels array — 0=Normal, 1=Suspicious, 2=Malicious
            eval_set: Optional [(X_val, y_val)] for early stopping
            early_stopping_rounds: Rounds without improvement before stopping
        """
        self._model = self.build_model()

        # Compute sample weights to balance rare malicious class
        from sklearn.utils.class_weight import compute_sample_weight
        weights = compute_sample_weight("balanced", y)

        fit_kwargs = dict(sample_weight=weights)
        if eval_set:
            fit_kwargs["eval_set"] = eval_set
            fit_kwargs["early_stopping_rounds"] = early_stopping_rounds
            fit_kwargs["verbose"] = False

        self._model.fit(X, y, **fit_kwargs)
        self._fitted = True
        logger.info(f"ThreatClassifier trained on {len(y)} samples "
                    f"| classes={np.unique(y, return_counts=True)}")

    def predict(self, X: np.ndarray) -> list[ThreatResult]:
        """
        Run inference on scaled feature matrix X.

        Returns a ThreatResult per row.
        Falls back to a rule-based heuristic if model is not fitted.
        """
        if not self._fitted or self._model is None:
            logger.warning("Model not fitted — using heuristic fallback")
            return self._heuristic_predict(X)

        # Shape guard
        if X.ndim == 1:
            X = X.reshape(1, -1)

        probs = self._model.predict_proba(X)   # (n, 3)
        results = []
        for row in probs:
            label_id = int(np.argmax(row))
            results.append(ThreatResult(
                label=LABEL_MAP[label_id],
                label_id=label_id,
                prob_normal=round(float(row[0]), 4),
                prob_suspicious=round(float(row[1]), 4),
                prob_malicious=round(float(row[2]), 4),
                confidence=round(float(row[label_id]), 4),
                color=LABEL_COLORS[label_id],
            ))
        return results

    # ------------------------------------------------------------------
    # Persistence
    # ------------------------------------------------------------------

    def save(self, path: Optional[Path] = None) -> None:
        path = path or self.DEFAULT_MODEL_PATH
        path.parent.mkdir(parents=True, exist_ok=True)
        joblib.dump(self._model, path)
        logger.info(f"ThreatClassifier saved → {path}")

    def load(self, path: Optional[Path] = None) -> bool:
        path = path or self.DEFAULT_MODEL_PATH
        if not path.exists():
            logger.warning(f"Model file not found: {path}")
            return False
        self._model = joblib.load(path)
        self._fitted = True
        logger.info(f"ThreatClassifier loaded ← {path}")
        return True

    # ------------------------------------------------------------------
    # Heuristic fallback (used before model is trained)
    # Classifies based on simple port / frequency rules
    # ------------------------------------------------------------------

    def _heuristic_predict(self, X: np.ndarray) -> list[ThreatResult]:
        """
        Rule-based classification used when no trained model exists.
        Column indices are mapped to FEATURE_COLS in preprocessor.py:
          0=packet_length, 1=ttl, 2=src_port, 3=dst_port,
          4=conn_frequency, 5=flow_duration
        """
        results = []
        for row in X:
            conn_freq = row[4]  # conn_frequency (raw, before scaling)
            dst_port = row[3]
            pkt_len = row[0]

            # Very high connection frequency → likely scan or DoS
            if conn_freq > 500:
                label_id = 2  # Malicious
                probs = (0.05, 0.15, 0.80)
            elif conn_freq > 100 or dst_port in [22, 23, 3389, 445]:
                label_id = 1  # Suspicious
                probs = (0.20, 0.60, 0.20)
            else:
                label_id = 0  # Normal
                probs = (0.90, 0.07, 0.03)

            results.append(ThreatResult(
                label=LABEL_MAP[label_id],
                label_id=label_id,
                prob_normal=probs[0],
                prob_suspicious=probs[1],
                prob_malicious=probs[2],
                confidence=probs[label_id],
                color=LABEL_COLORS[label_id],
            ))
        return results
