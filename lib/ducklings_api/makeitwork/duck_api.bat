@echo off
echo ==========================================
echo   🚀 Starting Duckling Flask API
echo ==========================================

if not exist "duckling_env" (
    echo ❌ Environment not found! Run setup_duckling.bat first.
    pause
    exit /b
)

echo 🔧 Activating virtual environment...
call duckling_env\Scripts\activate.bat

echo ==========================================
echo   ✅ Running Flask API on localhost:5000
echo ==========================================
cd duckling_env
python main.py

pause
