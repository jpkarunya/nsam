"""
MODULE 5 — Behavioral Anomaly Detection (K-Means Clustering)
=============================================================
Detects abnormal traffic patterns that the supervised classifier may miss
(e.g., slow-and-low attacks, new zero-day patterns).

How it works:
  1. Train K-Means on "normal" traffic to learn typical cluster centroids
  2. At inference, compute each packet's Euclidean distance to its nearest centroid
  3. Normalize distances to [0, 1] using the 95th-percentile from training
  4. High distance score → anomalous behaviour

Why K-Means for anomaly detection?
  - Unsupervised: no malicious labels needed for training
  - Fast inference (O(k·d) per sample)
  - Interpretable: "packet is X times farther than normal"

Design:
  - K is set empirically; default K=8 covers typical traffic profiles:
    (web, DNS, streaming, SSH, database, broadcast, ICMP, unknown)
  - We store the 95th-percentile distance from training to normalize scores
"""

from __future__ import annotations

import numpy as np
import joblib
from dataclasses import dataclass
from pathlib import Path
from typing import Optional
from sklearn.cluster import MiniBatchKMeans
from loguru import logger


# ---------------------------------------------------------------------------
# Output data class
# ---------------------------------------------------------------------------

@dataclass
class AnomalyResult:
    cluster_id: int         # Which cluster the packet was assigned to
    distance: float         # Raw Euclidean distance to centroid
    anomaly_score: float    # Normalized [0, 1] — higher = more anomalous
    is_anomaly: bool        # True if anomaly_score > threshold


# ---------------------------------------------------------------------------
# Detector
# ---------------------------------------------------------------------------

class AnomalyDetector:
    """
    K-Means based unsupervised anomaly detection.

    Attributes:
        n_clusters    Number of clusters (K). Rule of thumb: sqrt(n_samples/2)
        threshold     anomaly_score above which a packet is flagged as anomaly
        _p95_distance 95th-percentile distance from training, used for normalization
    """

    DEFAULT_MODEL_PATH = Path(__file__).parent.parent / "models" / "kmeans_anomaly.joblib"

    def __init__(self, n_clusters: int = 8, threshold: float = 0.75):
        self.n_clusters = n_clusters
        self.threshold = threshold
        self._model: Optional[MiniBatchKMeans] = None
        self._p95_distance: float = 1.0    # Updated after fit
        self._fitted = False

    # ------------------------------------------------------------------
    # Training
    # ------------------------------------------------------------------

    def fit(self, X: np.ndarray) -> None:
        """
        Fit K-Means on (preferably normal/baseline) traffic data.

        Uses MiniBatchKMeans for scalability to large pcap datasets.

        Args:
            X: Scaled feature matrix, shape (n_samples, n_features)
        """
        self._model = MiniBatchKMeans(
            n_clusters=self.n_clusters,
            batch_size=1024,
            max_iter=300,
            random_state=42,
            n_init=10,
        )
        self._model.fit(X)

        # Compute training distances to calibrate normalization
        distances = self._compute_distances(X)
        self._p95_distance = float(np.percentile(distances, 95))
        if self._p95_distance == 0:
            self._p95_distance = 1.0  # safety guard

        self._fitted = True
        inertia = self._model.inertia_
        logger.info(
            f"AnomalyDetector fitted | K={self.n_clusters} "
            f"inertia={inertia:.2f} p95_dist={self._p95_distance:.4f}"
        )

    # ------------------------------------------------------------------
    # Inference
    # ------------------------------------------------------------------

    def predict(self, X: np.ndarray) -> list[AnomalyResult]:
        """
        Score each sample in X for anomalousness.

        Returns a list of AnomalyResult, one per row.
        """
        if not self._fitted or self._model is None:
            logger.warning("AnomalyDetector not fitted — returning zero scores")
            return [AnomalyResult(0, 0.0, 0.0, False) for _ in range(len(X))]

        if X.ndim == 1:
            X = X.reshape(1, -1)

        cluster_ids = self._model.predict(X)
        distances = self._compute_distances(X)

        results = []
        for cid, dist in zip(cluster_ids, distances):
            # Normalize: score = dist / p95. Values > 1.0 are super-anomalous
            raw_score = dist / self._p95_distance
            # Sigmoid-like clamp to [0, 1]: score=1 when dist = 3×p95
            score = float(np.clip(raw_score / 3.0, 0.0, 1.0))
            results.append(AnomalyResult(
                cluster_id=int(cid),
                distance=round(float(dist), 6),
                anomaly_score=round(score, 4),
                is_anomaly=score > self.threshold,
            ))
        return results

    # ------------------------------------------------------------------
    # Persistence
    # ------------------------------------------------------------------

    def save(self, path: Optional[Path] = None) -> None:
        path = path or self.DEFAULT_MODEL_PATH
        path.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "model": self._model,
            "p95_distance": self._p95_distance,
            "n_clusters": self.n_clusters,
            "threshold": self.threshold,
        }
        joblib.dump(payload, path)
        logger.info(f"AnomalyDetector saved → {path}")

    def load(self, path: Optional[Path] = None) -> bool:
        path = path or self.DEFAULT_MODEL_PATH
        if not path.exists():
            logger.warning(f"Anomaly model not found: {path}")
            return False
        payload = joblib.load(path)
        self._model = payload["model"]
        self._p95_distance = payload["p95_distance"]
        self.n_clusters = payload["n_clusters"]
        self.threshold = payload["threshold"]
        self._fitted = True
        logger.info(f"AnomalyDetector loaded ← {path}")
        return True

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _compute_distances(self, X: np.ndarray) -> np.ndarray:
        """
        Compute Euclidean distance from each sample to its assigned centroid.
        """
        centers = self._model.cluster_centers_   # (k, d)
        labels = self._model.predict(X)           # (n,)
        assigned_centers = centers[labels]        # (n, d)
        diffs = X - assigned_centers
        return np.sqrt((diffs ** 2).sum(axis=1))  # (n,)
