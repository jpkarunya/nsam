@echo off
title NetGuard Backend
color 0A

REM ── CRITICAL FIX: always cd to the folder this .bat file is in ──
cd /d "%~dp0"
echo Working directory: %CD%
echo.

echo ================================================
echo   NETGUARD AI Backend - Starting...
echo ================================================
echo.

REM --- Step 1: Check Python ---
echo [STEP 1] Checking Python...
python --version
if errorlevel 1 (
    color 0C
    echo ERROR: Python not found!
    echo Install from https://python.org  -  tick "Add Python to PATH"
    pause & exit /b 1
)
echo Python OK!
echo.

REM --- Step 2: Create venv ---
echo [STEP 2] Setting up virtual environment...
if not exist "venv" (
    python -m venv venv
    if errorlevel 1 ( echo ERROR: venv failed & pause & exit /b 1 )
    echo Virtual environment created!
) else (
    echo Already exists, skipping.
)
echo.

REM --- Step 3: Activate venv ---
echo [STEP 3] Activating...
call "%~dp0venv\Scripts\activate.bat"
if errorlevel 1 ( echo ERROR: activation failed & pause & exit /b 1 )
echo Activated!
echo.

REM --- Step 4: Upgrade pip ---
echo [STEP 4] Upgrading pip...
python -m pip install --upgrade pip -q
echo.

REM --- Step 5: Install packages ---
echo [STEP 5] Installing packages...
pip install fastapi==0.111.0 "uvicorn[standard]==0.29.0" pydantic==2.7.1 python-multipart==0.0.9 -q
if errorlevel 1 ( echo ERROR installing fastapi & pause & exit /b 1 )
pip install scikit-learn==1.4.2 xgboost==2.0.3 numpy==1.26.4 pandas==2.2.2 joblib==1.4.2 -q
if errorlevel 1 ( echo ERROR installing ML packages & pause & exit /b 1 )
pip install sqlalchemy==2.0.30 aiosqlite==0.20.0 loguru==0.7.2 -q
if errorlevel 1 ( echo ERROR installing DB packages & pause & exit /b 1 )
pip install scapy==2.5.0 -q
echo All packages installed!
echo.

REM --- Step 6: Train ML models (run from correct directory) ---
echo [STEP 6] Training ML models...
if not exist "models" mkdir models
if not exist "models\xgb_classifier.joblib" (
    echo Training on 15000 samples - takes ~60 seconds...
    python "%~dp0ml\model_trainer.py"
    if errorlevel 1 (
        echo WARNING: Training failed - server will use heuristic fallback
    ) else (
        echo Models trained OK!
    )
) else (
    echo Models already trained, skipping.
)
echo.

REM --- Step 7: Start server (from correct directory) ---
echo ================================================
echo   BACKEND ONLINE: http://localhost:8000
echo   API Docs:        http://localhost:8000/docs
echo   Flutter app:     refresh the browser tab
echo   Press CTRL+C to stop
echo ================================================
echo.

python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload

echo.
echo Server stopped.
pause
