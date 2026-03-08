"""
MODULE 8 — Threat Logs Database
=================================
SQLAlchemy ORM models for threat event persistence.
Supports both SQLite (development) and PostgreSQL (production).
"""

import time
from sqlalchemy import (
    Column, Integer, Float, String, Boolean, Text,
    create_engine, Index
)
from sqlalchemy.orm import DeclarativeBase, sessionmaker, Session
from sqlalchemy.pool import StaticPool
from pathlib import Path
from loguru import logger


# ---------------------------------------------------------------------------
# Base class
# ---------------------------------------------------------------------------

class Base(DeclarativeBase):
    pass


# ---------------------------------------------------------------------------
# ORM Models
# ---------------------------------------------------------------------------

class ThreatEvent(Base):
    """
    Stores one threat detection event per packet or batch analysis.
    """
    __tablename__ = "threat_events"

    id = Column(Integer, primary_key=True, autoincrement=True)
    timestamp = Column(Float, nullable=False, index=True)

    # Source packet info
    src_ip = Column(String(45), nullable=False)   # IPv4 or IPv6
    dst_ip = Column(String(45), nullable=False)
    src_port = Column(Integer, default=0)
    dst_port = Column(Integer, default=0)
    protocol = Column(String(10), default="TCP")
    packet_length = Column(Integer, default=0)

    # Classification result
    threat_label = Column(String(20), nullable=False)   # Normal/Suspicious/Malicious
    threat_label_id = Column(Integer, nullable=False)   # 0/1/2
    prob_normal = Column(Float, default=0.0)
    prob_suspicious = Column(Float, default=0.0)
    prob_malicious = Column(Float, default=0.0)
    confidence = Column(Float, default=0.0)

    # Anomaly detection result
    cluster_id = Column(Integer, default=0)
    anomaly_score = Column(Float, default=0.0)
    is_anomaly = Column(Boolean, default=False)

    # Combined threat score
    threat_score = Column(Float, nullable=False)
    severity = Column(String(10), nullable=False)  # LOW/MEDIUM/HIGH/CRITICAL

    # Meta
    conn_frequency = Column(Integer, default=0)
    flow_duration = Column(Float, default=0.0)

    # Composite index for efficient dashboard queries
    __table_args__ = (
        Index("ix_threat_events_timestamp_severity", "timestamp", "severity"),
    )

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "timestamp": self.timestamp,
            "src_ip": self.src_ip,
            "dst_ip": self.dst_ip,
            "src_port": self.src_port,
            "dst_port": self.dst_port,
            "protocol": self.protocol,
            "packet_length": self.packet_length,
            "threat_label": self.threat_label,
            "threat_label_id": self.threat_label_id,
            "prob_normal": self.prob_normal,
            "prob_suspicious": self.prob_suspicious,
            "prob_malicious": self.prob_malicious,
            "confidence": self.confidence,
            "cluster_id": self.cluster_id,
            "anomaly_score": self.anomaly_score,
            "is_anomaly": self.is_anomaly,
            "threat_score": self.threat_score,
            "severity": self.severity,
            "conn_frequency": self.conn_frequency,
            "flow_duration": self.flow_duration,
        }


class AggregateSnapshot(Base):
    """
    Hourly aggregate snapshot for the prediction engine.
    """
    __tablename__ = "aggregate_snapshots"

    id = Column(Integer, primary_key=True, autoincrement=True)
    timestamp = Column(Float, nullable=False, index=True)
    hour_bucket = Column(String(20), nullable=False)   # e.g. "2024-01-15T14:00"
    avg_threat_score = Column(Float, default=0.0)
    max_threat_score = Column(Float, default=0.0)
    total_packets = Column(Integer, default=0)
    malicious_count = Column(Integer, default=0)
    suspicious_count = Column(Integer, default=0)
    normal_count = Column(Integer, default=0)
    anomaly_count = Column(Integer, default=0)

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "timestamp": self.timestamp,
            "hour_bucket": self.hour_bucket,
            "avg_threat_score": self.avg_threat_score,
            "max_threat_score": self.max_threat_score,
            "total_packets": self.total_packets,
            "malicious_count": self.malicious_count,
            "suspicious_count": self.suspicious_count,
            "normal_count": self.normal_count,
            "anomaly_count": self.anomaly_count,
        }


# ---------------------------------------------------------------------------
# Database factory
# ---------------------------------------------------------------------------

DB_PATH = Path(__file__).parent.parent / "data" / "netguard.db"


def get_engine(db_url: str = None):
    """
    Create the SQLAlchemy engine.
    Defaults to SQLite for development; pass PostgreSQL URL for production.

    PostgreSQL example:
        db_url = "postgresql+asyncpg://user:password@localhost/netguard"
    """
    if db_url is None:
        DB_PATH.parent.mkdir(exist_ok=True)
        db_url = f"sqlite:///{DB_PATH}"
        engine = create_engine(
            db_url,
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
    else:
        engine = create_engine(db_url)

    logger.info(f"Database engine created: {db_url}")
    return engine


def init_db(engine=None) -> sessionmaker:
    """Initialize database tables and return a session factory."""
    if engine is None:
        engine = get_engine()
    Base.metadata.create_all(engine)
    logger.info("Database tables created/verified")
    return sessionmaker(bind=engine, expire_on_commit=False)


# ---------------------------------------------------------------------------
# Raw SQL Schema (for documentation / manual setup)
# ---------------------------------------------------------------------------

SCHEMA_SQL = """
-- NetGuard Threat Detection Database Schema
-- Compatible with SQLite and PostgreSQL

CREATE TABLE IF NOT EXISTS threat_events (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp       REAL    NOT NULL,
    src_ip          TEXT    NOT NULL,
    dst_ip          TEXT    NOT NULL,
    src_port        INTEGER DEFAULT 0,
    dst_port        INTEGER DEFAULT 0,
    protocol        TEXT    DEFAULT 'TCP',
    packet_length   INTEGER DEFAULT 0,
    threat_label    TEXT    NOT NULL,
    threat_label_id INTEGER NOT NULL,
    prob_normal     REAL    DEFAULT 0.0,
    prob_suspicious REAL    DEFAULT 0.0,
    prob_malicious  REAL    DEFAULT 0.0,
    confidence      REAL    DEFAULT 0.0,
    cluster_id      INTEGER DEFAULT 0,
    anomaly_score   REAL    DEFAULT 0.0,
    is_anomaly      INTEGER DEFAULT 0,  -- SQLite bool
    threat_score    REAL    NOT NULL,
    severity        TEXT    NOT NULL,
    conn_frequency  INTEGER DEFAULT 0,
    flow_duration   REAL    DEFAULT 0.0
);

CREATE INDEX IF NOT EXISTS ix_threat_events_timestamp
    ON threat_events(timestamp);
CREATE INDEX IF NOT EXISTS ix_threat_events_severity
    ON threat_events(severity);

CREATE TABLE IF NOT EXISTS aggregate_snapshots (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp        REAL    NOT NULL,
    hour_bucket      TEXT    NOT NULL,
    avg_threat_score REAL    DEFAULT 0.0,
    max_threat_score REAL    DEFAULT 0.0,
    total_packets    INTEGER DEFAULT 0,
    malicious_count  INTEGER DEFAULT 0,
    suspicious_count INTEGER DEFAULT 0,
    normal_count     INTEGER DEFAULT 0,
    anomaly_count    INTEGER DEFAULT 0
);
"""

if __name__ == "__main__":
    engine = get_engine()
    Base.metadata.create_all(engine)
    print("Database initialized at:", DB_PATH)
    print("\nSchema:")
    print(SCHEMA_SQL)
