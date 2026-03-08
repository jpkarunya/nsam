"""
NetGuard FastAPI Backend — Main Application
============================================
Entry point for the FastAPI server. Registers all route modules,
initializes the database, loads ML models on startup, and configures CORS
for the Flutter web client.

Start with:
    uvicorn main:app --reload --host 0.0.0.0 --port 8000
"""

from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from loguru import logger

from db.models import init_db
from ml.threat_classifier import ThreatClassifier
from ml.anomaly_detector import AnomalyDetector
from ml.preprocessor import FeatureEngineer
from ml.threat_scorer import ThreatScoringEngine, ThreatPredictionEngine

# Import route modules
from api.routes_scan import router as scan_router
from api.routes_detect import router as detect_router
from api.routes_predict import router as predict_router
from api.routes_logs import router as logs_router
from api.routes_dashboard import router as dashboard_router


# ---------------------------------------------------------------------------
# Application State (shared ML objects injected into request state)
# ---------------------------------------------------------------------------

class AppState:
    """Holds all singleton ML objects loaded at startup."""
    classifier: ThreatClassifier
    anomaly_detector: AnomalyDetector
    feature_engineer: FeatureEngineer
    scoring_engine: ThreatScoringEngine
    prediction_engine: ThreatPredictionEngine
    db_session_factory = None


app_state = AppState()
MODELS_DIR = Path(__file__).parent / "models"
SCALER_PATH = MODELS_DIR / "scaler.joblib"


# ---------------------------------------------------------------------------
# Lifespan (startup + shutdown)
# ---------------------------------------------------------------------------

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Load models and init DB on startup; cleanup on shutdown."""
    logger.info("🚀 NetGuard backend starting up...")

    # --- Database ---
    app_state.db_session_factory = init_db()
    logger.info("✅ Database initialized")

    # --- ML Models ---
    app_state.feature_engineer = FeatureEngineer()
    if SCALER_PATH.exists():
        app_state.feature_engineer.load_scaler(str(SCALER_PATH))

    app_state.classifier = ThreatClassifier()
    loaded_cls = app_state.classifier.load()
    if not loaded_cls:
        logger.warning("⚠️  Classifier model not found — using heuristic fallback")

    app_state.anomaly_detector = AnomalyDetector()
    loaded_ano = app_state.anomaly_detector.load()
    if not loaded_ano:
        logger.warning("⚠️  Anomaly model not found — scores will be zero")

    app_state.scoring_engine = ThreatScoringEngine()
    app_state.prediction_engine = ThreatPredictionEngine()

    logger.info("✅ ML models loaded")
    logger.info("🛡️  NetGuard is ready — http://0.0.0.0:8000")

    yield  # App runs here

    # Shutdown
    logger.info("👋 NetGuard shutting down...")
    from ml.packet_capture import capture_engine
    if capture_engine.is_running():
        capture_engine.stop()


# ---------------------------------------------------------------------------
# FastAPI App
# ---------------------------------------------------------------------------

app = FastAPI(
    title="NetGuard — AI Threat Detection API",
    description="Predictive AI-based network threat detection backend",
    version="1.0.0",
    lifespan=lifespan,
)

# CORS: allow Flutter web to call the API
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],   # In production: restrict to your Flutter domain
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Inject app_state into every request
@app.middleware("http")
async def attach_state(request, call_next):
    request.state.app = app_state
    response = await call_next(request)
    return response

# Register routers
app.include_router(scan_router,      prefix="/scan",      tags=["Scanning"])
app.include_router(detect_router,    prefix="",           tags=["Detection"])
app.include_router(predict_router,   prefix="",           tags=["Prediction"])
app.include_router(logs_router,      prefix="",           tags=["Logs"])
app.include_router(dashboard_router, prefix="",           tags=["Dashboard"])


@app.get("/health")
async def health():
    return {"status": "ok", "version": "1.0.0"}
