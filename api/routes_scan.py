"""
API Routes — Scan
  POST /scan/start   → Start live packet capture
  POST /scan/stop    → Stop capture
  GET  /scan/status  → Status + drained packets
"""

import time
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from ml.packet_capture import capture_engine

router = APIRouter()


class ScanConfig(BaseModel):
    interface: str | None = None
    max_packets: int = 50


@router.post("/start")
async def start_scan(config: ScanConfig):
    capture_engine._iface = config.interface
    result = capture_engine.start()
    if not result.get("ok"):
        raise HTTPException(status_code=503, detail=result.get("reason", "Cannot start capture"))
    return {"status": "started", "interface": config.interface or "default"}


@router.post("/stop")
async def stop_scan():
    capture_engine.stop()
    return {"status": "stopped", "stats": capture_engine.get_stats()}


@router.get("/status")
async def scan_status(max_packets: int = 20):
    packets = capture_engine.drain(max_records=max_packets)
    return {
        "running": capture_engine.is_running(),
        "stats": capture_engine.get_stats(),
        "packets": [p.to_dict() for p in packets],
        "timestamp": time.time(),
    }
