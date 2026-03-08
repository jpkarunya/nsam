"""
MODULE 1 — Live Network Traffic Capture
========================================
Windows-safe version: Scapy is imported lazily (only when capture starts),
so the server starts even if Npcap/WinPcap is not installed.
"""

import time
import threading
from collections import defaultdict, deque
from dataclasses import dataclass, field, asdict
from queue import Queue, Empty
from typing import Optional

from loguru import logger

# ---------------------------------------------------------------------------
# Data structure for a single captured network event
# ---------------------------------------------------------------------------

@dataclass
class PacketRecord:
    timestamp: float
    src_ip: str
    dst_ip: str
    src_port: int
    dst_port: int
    protocol: str
    packet_length: int
    ttl: int
    flags: str
    conn_frequency: int = 0
    flow_duration: float = 0.0

    def to_dict(self) -> dict:
        return asdict(self)


# ---------------------------------------------------------------------------
# Per-flow state tracker
# ---------------------------------------------------------------------------

class FlowTracker:
    WINDOW_SECONDS = 60

    def __init__(self):
        self._timestamps: dict[tuple, deque] = defaultdict(deque)
        self._first_seen: dict[tuple, float] = {}
        self._lock = threading.Lock()

    def update(self, src_ip, dst_ip, dst_port, protocol, now) -> tuple[int, float]:
        key = (src_ip, dst_ip, dst_port, protocol)
        with self._lock:
            if key not in self._first_seen:
                self._first_seen[key] = now
            flow_duration = now - self._first_seen[key]
            dq = self._timestamps[key]
            cutoff = now - self.WINDOW_SECONDS
            while dq and dq[0] < cutoff:
                dq.popleft()
            dq.append(now)
            conn_frequency = len(dq)
        return conn_frequency, flow_duration


# ---------------------------------------------------------------------------
# Packet Capture Engine — Scapy imported LAZILY (Windows-safe)
# ---------------------------------------------------------------------------

class PacketCaptureEngine:
    def __init__(self, iface: Optional[str] = None, packet_queue_maxsize: int = 10_000):
        self._iface = iface
        self._sniffer = None
        self._running = False
        self._queue: Queue[PacketRecord] = Queue(maxsize=packet_queue_maxsize)
        self._flow_tracker = FlowTracker()
        self._stats = {"captured": 0, "dropped": 0}
        self._lock = threading.Lock()
        self._scapy_available = None  # None = not yet checked

    def _check_scapy(self) -> bool:
        """Try to import scapy. Returns True if available."""
        if self._scapy_available is not None:
            return self._scapy_available
        try:
            from scapy.all import AsyncSniffer, IP, TCP, UDP, ICMP  # noqa
            self._scapy_available = True
            logger.info("Scapy loaded successfully")
        except Exception as e:
            self._scapy_available = False
            logger.warning(f"Scapy not available: {e}. Live capture disabled.")
        return self._scapy_available

    def start(self) -> dict:
        with self._lock:
            if self._running:
                return {"ok": False, "reason": "Already running"}

            if not self._check_scapy():
                return {
                    "ok": False,
                    "reason": (
                        "Scapy/Npcap not available on this system. "
                        "Install Npcap from https://npcap.com then restart the backend."
                    )
                }

            try:
                from scapy.all import AsyncSniffer
                self._sniffer = AsyncSniffer(
                    iface=self._iface,
                    prn=self._handle_packet,
                    store=False,
                    filter="ip",
                )
                self._sniffer.start()
                self._running = True
                logger.info(f"Capture started on iface={self._iface or 'default'}")
                return {"ok": True}
            except Exception as e:
                logger.error(f"Capture start failed: {e}")
                return {"ok": False, "reason": str(e)}

    def stop(self) -> None:
        with self._lock:
            if not self._running:
                return
            if self._sniffer:
                try:
                    self._sniffer.stop()
                except Exception:
                    pass
                self._sniffer = None
            self._running = False
            logger.info("Capture stopped")

    def is_running(self) -> bool:
        return self._running

    def drain(self, max_records: int = 100) -> list[PacketRecord]:
        records = []
        for _ in range(max_records):
            try:
                records.append(self._queue.get_nowait())
            except Empty:
                break
        return records

    def get_stats(self) -> dict:
        return dict(self._stats, queue_size=self._queue.qsize())

    def _handle_packet(self, pkt) -> None:
        try:
            from scapy.all import IP, TCP, UDP, ICMP
            if not pkt.haslayer(IP):
                return
            ip = pkt[IP]
            now = time.time()

            if pkt.haslayer(TCP):
                layer = pkt[TCP]
                protocol, src_port, dst_port = "TCP", int(layer.sport), int(layer.dport)
                flags = str(layer.flags)
            elif pkt.haslayer(UDP):
                layer = pkt[UDP]
                protocol, src_port, dst_port = "UDP", int(layer.sport), int(layer.dport)
                flags = ""
            elif pkt.haslayer(ICMP):
                protocol, src_port, dst_port, flags = "ICMP", 0, 0, ""
            else:
                protocol, src_port, dst_port, flags = "OTHER", 0, 0, ""

            conn_freq, flow_dur = self._flow_tracker.update(
                str(ip.src), str(ip.dst), dst_port, protocol, now)

            record = PacketRecord(
                timestamp=now, src_ip=str(ip.src), dst_ip=str(ip.dst),
                src_port=src_port, dst_port=dst_port, protocol=protocol,
                packet_length=int(ip.len) if ip.len else len(pkt),
                ttl=int(ip.ttl), flags=flags,
                conn_frequency=conn_freq, flow_duration=round(flow_dur, 4),
            )

            if not self._queue.full():
                self._queue.put_nowait(record)
                self._stats["captured"] += 1
            else:
                self._stats["dropped"] += 1

        except Exception as exc:
            logger.debug(f"Packet parse error: {exc}")


# Singleton
capture_engine = PacketCaptureEngine()
