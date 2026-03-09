from fastapi import APIRouter
from pydantic import BaseModel
import time

router = APIRouter()

class ScanConfig(BaseModel):
    interface: str | None = None
    max_packets: int = 50

@router.post("/start")
async def start_scan(config: ScanConfig):
    try:
        from ml.packet_capture import capture_engine
        capture_engine._iface = config.interface
        result = capture_engine.start()
        if not result.get("ok"):
            return {
                "status": "unavailable",
                "message": result.get("reason", "Capture unavailable"),
                "interface": config.interface or "default"
            }
        return {"status": "started", "interface": config.interface or "default"}
    except Exception as e:
        return {"status": "unavailable", "message": str(e)}

@router.post("/stop")
async def stop_scan():
    try:
        from ml.packet_capture import capture_engine
        capture_engine.stop()
        return {"status": "stopped"}
    except:
        return {"status": "stopped"}

@router.get("/status")
async def scan_status(max_packets: int = 20):
    try:
        from ml.packet_capture import capture_engine
        packets = capture_engine.drain(max_records=max_packets)
        return {
            "running": capture_engine.is_running(),
            "stats": capture_engine.get_stats(),
            "packets": [p.to_dict() for p in packets],
            "timestamp": time.time(),
        }
    except:
        return {
            "running": False,
            "stats": {},
            "packets": [],
            "timestamp": time.time()
        }
