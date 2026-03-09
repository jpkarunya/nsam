from fastapi import APIRouter, Request
import time, random

router = APIRouter()

@router.get("/dashboard-data")
async def dashboard_data(request: Request):
    try:
        app = request.app
        db = app.state.db if hasattr(app.state, 'db') else None

        return {
            "threat_score": round(random.uniform(5, 45), 1),
            "severity": "LOW",
            "total_packets": random.randint(100, 5000),
            "anomalies": random.randint(0, 10),
            "malicious": random.randint(0, 5),
            "suspicious": random.randint(0, 15),
            "top_sources": [
                {"ip": "192.168.1.1", "count": 120},
                {"ip": "10.0.0.1", "count": 85},
                {"ip": "172.16.0.1", "count": 43},
            ],
            "trend": [
                {"time": i, "score": round(random.uniform(2, 40), 1)}
                for i in range(24)
            ],
            "status": "active",
            "timestamp": time.time()
        }
    except Exception as e:
        return {
            "threat_score": 0.0,
            "severity": "LOW",
            "total_packets": 0,
            "anomalies": 0,
            "malicious": 0,
            "suspicious": 0,
            "top_sources": [],
            "trend": [],
            "status": "error",
            "timestamp": time.time()
        }
