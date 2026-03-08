import time
from fastapi import APIRouter, Request
from pydantic import BaseModel
from ml.preprocessor import DataPreprocessor, FeatureEngineer
from ml.packet_capture import PacketRecord

router = APIRouter()

class PacketData(BaseModel):
    src_ip: str = "192.168.1.1"
    dst_ip: str = "8.8.8.8"
    src_port: int = 12345
    dst_port: int = 80
    protocol: str = "TCP"
    packet_length: int = 500
    ttl: int = 64
    flags: str = "SA"
    conn_frequency: int = 5
    flow_duration: float = 1.2
    timestamp: float = 0.0

class DetectRequest(BaseModel):
    packets: list[PacketData]

@router.post("/detect")
async def detect_threats(request: Request, body: DetectRequest):
    state = request.state.app
    records = [
        PacketRecord(
            timestamp=p.timestamp or time.time(),
            src_ip=p.src_ip, dst_ip=p.dst_ip,
            src_port=p.src_port, dst_port=p.dst_port,
            protocol=p.protocol, packet_length=p.packet_length,
            ttl=p.ttl, flags=p.flags,
            conn_frequency=p.conn_frequency, flow_duration=p.flow_duration,
        )
        for p in body.packets
    ]

    preprocessor = DataPreprocessor()
    clean_df = preprocessor.clean(records)
    feature_df = state.feature_engineer.build_features(clean_df)
    X = state.feature_engineer.transform(feature_df)

    classifications = state.classifier.predict(X)
    anomalies = state.anomaly_detector.predict(X)
    scores, aggregate_score = state.scoring_engine.score_batch(classifications, anomalies)

    results = []
    if state.db_session_factory:
        from db.models import ThreatEvent
        with state.db_session_factory() as session:
            for i, (rec, cls, ano, sc) in enumerate(zip(records, classifications, anomalies, scores)):
                event = ThreatEvent(
                    timestamp=rec.timestamp,
                    src_ip=rec.src_ip, dst_ip=rec.dst_ip,
                    src_port=rec.src_port, dst_port=rec.dst_port,
                    protocol=rec.protocol, packet_length=rec.packet_length,
                    threat_label=cls.label, threat_label_id=cls.label_id,
                    prob_normal=cls.prob_normal, prob_suspicious=cls.prob_suspicious,
                    prob_malicious=cls.prob_malicious, confidence=cls.confidence,
                    cluster_id=ano.cluster_id, anomaly_score=ano.anomaly_score,
                    is_anomaly=ano.is_anomaly, threat_score=sc.raw_score,
                    severity=sc.severity, conn_frequency=rec.conn_frequency,
                    flow_duration=rec.flow_duration,
                )
                session.add(event)
                results.append({
                    "packet_index": i,
                    "src_ip": rec.src_ip, "dst_ip": rec.dst_ip,
                    "protocol": rec.protocol,
                    "threat_label": cls.label,
                    "threat_score": sc.raw_score,
                    "severity": sc.severity,
                    "severity_color": sc.severity_color,
                    "anomaly_score": ano.anomaly_score,
                    "is_anomaly": ano.is_anomaly,
                    "prob_malicious": cls.prob_malicious,
                })
            session.commit()
            state.prediction_engine.add_observation(aggregate_score)

    return {
        "aggregate_threat_score": aggregate_score,
        "packet_count": len(records),
        "results": results,
        "timestamp": time.time(),
    }
