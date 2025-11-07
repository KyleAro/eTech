@echo off
echo ==========================================
echo   🚀 Setting up Duckling API Environment
echo ==========================================

python --version >nul 2>&1
if errorlevel 1 (
    echo ❌ Python not found! Please install Python 3.8+ and add it to PATH.
    pause
    exit /b
)

if not exist "duckling_env" (
    echo 📂 Creating virtual environment...
    python -m venv duckling_env
)

echo 🔧 Activating virtual environment...
call duckling_env\Scripts\activate.bat

echo 📦 Upgrading pip...
python -m pip install --upgrade pip

echo 📦 Installing required Python packages...
pip install flask librosa numpy joblib scikit-learn pydub

:: --- Add FFmpeg to system PATH if not present ---
set "FFMPEG_PATH=C:\ffmpeg\bin"
ffmpeg -version >nul 2>&1
if errorlevel 1 (
    echo ⚠️ FFmpeg not found in PATH. Attempting to add it...
    for /f "tokens=2*" %%A in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path') do set "CURRENT_PATH=%%B"

    echo %CURRENT_PATH% | find /I "%FFMPEG_PATH%" >nul
    if errorlevel 1 (
        setx /M PATH "%CURRENT_PATH%;%FFMPEG_PATH%"
        echo ✅ FFmpeg path added to system PATH. You may need to restart CMD or PC.
    ) else (
        echo FFmpeg path already exists in system PATH.
    )
) else (
    echo ✅ FFmpeg detected in PATH.
)

echo 📂 Copying Duckling API files into environment...
xcopy "C:\Users\User\etech\lib\python\main.py" "duckling_env\" /Y
xcopy "C:\Users\User\etech\lib\python\duckling_svm_rbf_day4-13.pkl" "duckling_env\" /Y
xcopy "C:\Users\User\etech\lib\python\duckling_scaler_day4-13.pkl" "duckling_env\" /Y

echo ==========================================
echo   ✅ Setup complete! You can now run the API
echo ==========================================
pause
