"""
MODULE 6 — Dynamic Threat Scoring Engine
MODULE 7 — Threat Prediction Engine
=========================================

MODULE 6: Combines XGBoost classification probability with the K-Means
anomaly distance score to produce a single, interpretable threat score
in the range [0, 100].

Formula:
    threat_score = (prob_malicious × 70) + (anomaly_score × 30)
    where both inputs are in [0, 1]

The 70/30 weighting reflects:
  - The supervised classifier (XGBoost) is more precise on known attack types
  - The anomaly detector catches unknown/novel behaviour
  - Combined they cover both known and unknown threats

MODULE 7: Uses historical threat scores to predict future risk levels
via a combined moving average + linear trend approach.

Prediction method:
  - Short-term (1h): Exponentially Weighted Moving Average (EWMA)
  - Long-term (24h): Linear regression on last N hours of scores
  - Output: predicted scores for next 24 time buckets
"""

from __future__ import annotations

import time
import numpy as np
from collections import deque
from dataclasses import dataclass, field
from typing import Optional

from .threat_classifier import ThreatResult
from .anomaly_detector import AnomalyResult
from loguru import logger


# ===========================================================================
# MODULE 6: Dynamic Threat Scoring Engine
# ===========================================================================

@dataclass
class ThreatScore:
    raw_score: float          # 0–100 combined score
    classification_part: float  # Contribution from XGBoost (0–70)
    anomaly_part: float       # Contribution from K-Means (0–30)
    severity: str             # "LOW" | "MEDIUM" | "HIGH" | "CRITICAL"
    severity_color: str       # Hex color for UI
    timestamp: float = field(default_factory=time.time)


def _severity_from_score(score: float) -> tuple[str, str]:
    """Map 0–100 score to severity label and UI color."""
    if score < 25:
        return "LOW", "#00FF88"
    elif score < 50:
        return "MEDIUM", "#FFB800"
    elif score < 75:
        return "HIGH", "#FF6B00"
    else:
        return "CRITICAL", "#FF3366"


class ThreatScoringEngine:
    """
    Computes a single 0–100 threat score by combining:
      - XGBoost malicious probability  (weight: 70%)
      - K-Means anomaly score           (weight: 30%)

    Can also compute aggregate scores for a batch of packets.
    """

    XGB_WEIGHT = 0.70
    ANOMALY_WEIGHT = 0.30

    def score_single(
        self,
        classification: ThreatResult,
        anomaly: AnomalyResult,
    ) -> ThreatScore:
        """Score a single packet using its classification and anomaly results."""
        cls_part = classification.prob_malicious * 100 * self.XGB_WEIGHT
        ano_part = anomaly.anomaly_score * 100 * self.ANOMALY_WEIGHT
        raw = min(cls_part + ano_part, 100.0)
        severity, color = _severity_from_score(raw)

        return ThreatScore(
            raw_score=round(raw, 2),
            classification_part=round(cls_part, 2),
            anomaly_part=round(ano_part, 2),
            severity=severity,
            severity_color=color,
        )

    def score_batch(
        self,
        classifications: list[ThreatResult],
        anomalies: list[AnomalyResult],
    ) -> tuple[list[ThreatScore], float]:
        """
        Score a batch of packets.

        Returns:
            - List of individual ThreatScore objects
            - Aggregate score for the batch (max of top-10% scores)
              The max-percentile approach surfaces true attack traffic
              that might be hidden in a large volume of normal packets.
        """
        scores = [
            self.score_single(c, a)
            for c, a in zip(classifications, anomalies)
        ]

        if scores:
            raw_values = [s.raw_score for s in scores]
            # Aggregate = 90th percentile (captures worst-case in batch)
            aggregate = float(np.percentile(raw_values, 90))
        else:
            aggregate = 0.0

        return scores, round(aggregate, 2)


# ===========================================================================
# MODULE 7: Threat Prediction Engine
# ===========================================================================

@dataclass
class PredictionPoint:
    bucket_index: int       # 0 = "now+1h", 1 = "now+2h", etc.
    predicted_score: float  # 0–100
    confidence: float       # 0–1 (higher = more confident)
    label: str              # Human-readable time label


class ThreatPredictionEngine:
    """
    Predicts future threat risk levels from historical score time-series.

    Algorithm:
      1. Maintain a rolling buffer of the last MAX_HISTORY aggregate scores
      2. Short-term trend: EWMA (responds quickly to recent spikes)
      3. Long-term trend: Ordinary Least Squares linear regression on last 24h
      4. Blend: prediction = 0.6 × EWMA + 0.4 × linear_trend
      5. Confidence decreases as prediction horizon increases

    Each "bucket" represents one time step. Default step = 1 hour.
    """

    MAX_HISTORY = 168          # 7 days × 24h
    PREDICT_STEPS = 24         # Predict next 24 hours
    EWMA_ALPHA = 0.3           # EWMA smoothing factor (0=slow, 1=instant)

    def __init__(self):
        self._history: deque[tuple[float, float]] = deque(maxlen=self.MAX_HISTORY)
        # Each entry is (timestamp, aggregate_threat_score)

    def add_observation(self, score: float, timestamp: Optional[float] = None) -> None:
        """Add a new aggregate threat score to the history buffer."""
        ts = timestamp or time.time()
        self._history.append((ts, score))

    def predict(self) -> list[PredictionPoint]:
        """
        Generate predictions for the next PREDICT_STEPS time buckets.

        Returns an empty list if there is insufficient history (< 4 points).
        """
        if len(self._history) < 4:
            logger.debug("Not enough history for prediction")
            return []

        scores = np.array([s for _, s in self._history], dtype=float)

        # --- EWMA: Exponentially Weighted Moving Average ---
        ewma = self._compute_ewma(scores)
        last_ewma = ewma[-1]

        # --- Linear trend via OLS on last min(48, len) points ---
        window = min(48, len(scores))
        trend_slope = self._linear_slope(scores[-window:])

        predictions = []
        for step in range(1, self.PREDICT_STEPS + 1):
            # EWMA component: damped toward last value
            ewma_pred = last_ewma + (trend_slope * step * self.EWMA_ALPHA)

            # Linear trend component
            linear_pred = scores[-1] + trend_slope * step

            # Blend
            blended = 0.6 * ewma_pred + 0.4 * linear_pred

            # Clamp to valid score range
            predicted = float(np.clip(blended, 0.0, 100.0))

            # Confidence degrades with prediction horizon
            confidence = max(0.10, 1.0 - (step / self.PREDICT_STEPS) * 0.8)

            predictions.append(PredictionPoint(
                bucket_index=step,
                predicted_score=round(predicted, 2),
                confidence=round(confidence, 3),
                label=f"+{step}h",
            ))

        return predictions

    def get_trend_summary(self) -> dict:
        """Return a summary of current trend direction and momentum."""
        if len(self._history) < 4:
            return {"trend": "insufficient_data", "slope": 0.0, "current_score": 0.0}

        scores = np.array([s for _, s in self._history])
        slope = self._linear_slope(scores[-24:] if len(scores) >= 24 else scores)
        current = float(scores[-1])

        if slope > 2.0:
            trend = "RISING_FAST"
        elif slope > 0.5:
            trend = "RISING"
        elif slope < -2.0:
            trend = "FALLING_FAST"
        elif slope < -0.5:
            trend = "FALLING"
        else:
            trend = "STABLE"

        return {
            "trend": trend,
            "slope_per_hour": round(float(slope), 4),
            "current_score": round(current, 2),
            "history_length": len(self._history),
        }

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _compute_ewma(self, scores: np.ndarray) -> np.ndarray:
        """Compute exponentially weighted moving average in-place."""
        ewma = np.zeros_like(scores)
        ewma[0] = scores[0]
        for i in range(1, len(scores)):
            ewma[i] = self.EWMA_ALPHA * scores[i] + (1 - self.EWMA_ALPHA) * ewma[i - 1]
        return ewma

    @staticmethod
    def _linear_slope(scores: np.ndarray) -> float:
        """Compute slope of OLS linear fit (score change per time unit)."""
        n = len(scores)
        if n < 2:
            return 0.0
        x = np.arange(n, dtype=float)
        # OLS slope: sum((x-x̄)(y-ȳ)) / sum((x-x̄)²)
        x_mean = x.mean()
        y_mean = scores.mean()
        numerator = float(((x - x_mean) * (scores - y_mean)).sum())
        denominator = float(((x - x_mean) ** 2).sum())
        return numerator / denominator if denominator != 0 else 0.0
