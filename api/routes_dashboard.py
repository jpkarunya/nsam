import time
from fastapi import APIRouter, Request

router = APIRouter()

@router.get("/dashboard-data")
async def get_dashboard_data(request: Request, hours: int = 24):
    state = request.state.app
    cutoff = time.time() - (hours * 3600)

    if not state.db_session_factory:
        return _empty()

    from db.models import ThreatEvent

    with state.db_session_factory() as session:
        recent = session.query(ThreatEvent).filter(ThreatEvent.timestamp >= cutoff).all()

    if not recent:
        return _empty()

    scores = [e.threat_score for e in recent]
    current_score = max(scores[-10:]) if len(scores) >= 10 else (max(scores) if scores else 0)

    label_counts = {"Normal": 0, "Suspicious": 0, "Malicious": 0}
    for e in recent:
        label_counts[e.threat_label] = label_counts.get(e.threat_label, 0) + 1

    from collections import Counter
    mal = [e for e in recent if e.threat_label == "Malicious"]
    top_sources = Counter(e.src_ip for e in mal).most_common(5)

    hourly = {}
    for e in recent:
        h = int(e.timestamp // 3600) * 3600
        hourly.setdefault(h, []).append(e.threat_score)

    trend_data = [
        {"timestamp": ts, "avg_score": sum(v)/len(v), "count": len(v)}
        for ts, v in sorted(hourly.items())
    ]

    preds = state.prediction_engine.predict()
    trend_summary = state.prediction_engine.get_trend_summary()

    return {
        "current_threat_score": round(current_score, 2),
        "severity": _sev(current_score),
        "total_packets_analyzed": len(recent),
        "label_distribution": label_counts,
        "top_threat_sources": [{"ip": ip, "count": c} for ip, c in top_sources],
        "hourly_trend": trend_data,
        "predictions": [{"label": p.label, "score": p.predicted_score, "confidence": p.confidence} for p in preds[:12]],
        "trend_summary": trend_summary,
        "anomaly_count": sum(1 for e in recent if e.is_anomaly),
        "timestamp": time.time(),
    }

def _empty():
    return {
        "current_threat_score": 0.0, "severity": "LOW",
        "total_packets_analyzed": 0,
        "label_distribution": {"Normal": 0, "Suspicious": 0, "Malicious": 0},
        "top_threat_sources": [], "hourly_trend": [], "predictions": [],
        "trend_summary": {"trend": "insufficient_data", "slope_per_hour": 0.0, "current_score": 0.0},
        "anomaly_count": 0, "timestamp": time.time(),
    }

def _sev(score):
    if score < 25: return "LOW"
    if score < 50: return "MEDIUM"
    if score < 75: return "HIGH"
    return "CRITICAL"
