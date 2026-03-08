import time
from fastapi import APIRouter, Request

router = APIRouter()

@router.get("/predict")
async def get_prediction(request: Request):
    state = request.state.app
    predictions = state.prediction_engine.predict()
    trend = state.prediction_engine.get_trend_summary()
    return {
        "predictions": [
            {"bucket_index": p.bucket_index, "label": p.label,
             "predicted_score": p.predicted_score, "confidence": p.confidence}
            for p in predictions
        ],
        "trend_summary": trend,
        "timestamp": time.time(),
    }
