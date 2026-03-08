import time
from typing import Optional
from fastapi import APIRouter, Request

router = APIRouter()

@router.get("/logs")
async def get_logs(
    request: Request,
    limit: int = 100,
    offset: int = 0,
    severity: Optional[str] = None,
    min_score: Optional[float] = None,
):
    state = request.state.app
    if not state.db_session_factory:
        return {"logs": [], "total": 0}

    from db.models import ThreatEvent
    from sqlalchemy import desc

    with state.db_session_factory() as session:
        query = session.query(ThreatEvent)
        if severity:
            query = query.filter(ThreatEvent.severity == severity.upper())
        if min_score is not None:
            query = query.filter(ThreatEvent.threat_score >= min_score)
        total = query.count()
        events = query.order_by(desc(ThreatEvent.timestamp)).offset(offset).limit(limit).all()

    return {
        "logs": [e.to_dict() for e in events],
        "total": total,
        "limit": limit,
        "offset": offset,
    }
