@echo off
REM Setup script for Circle of Trust test environment (Windows)

echo =========================================
echo Circle of Trust - Test Environment Setup
echo =========================================

REM Check if Python is available
where python >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Python is not installed or not in PATH
    exit /b 1
)

for /f "tokens=*" %%i in ('python --version') do set PYTHON_VERSION=%%i
echo ✓ Python found: %PYTHON_VERSION%

REM Create virtual environment
echo.
echo Creating virtual environment...
if exist "test-venv" (
    echo   Removing existing test-venv...
    rmdir /s /q test-venv
)

python -m venv test-venv
echo ✓ Virtual environment created

REM Activate virtual environment
echo.
echo Activating virtual environment...
call test-venv\Scripts\activate.bat

REM Upgrade pip
echo.
echo Upgrading pip...
python -m pip install --quiet --upgrade pip

REM Install test dependencies
echo.
echo Installing test dependencies...
pip install --quiet -r tests\requirements.txt
echo ✓ Dependencies installed

REM Verify installation
echo.
echo Verifying installation...
python -m pytest --version
echo ✓ pytest installed successfully

REM Test collection
echo.
echo Collecting tests...
python -m pytest tests\smoke\test_smoke.py --collect-only -q

echo.
echo =========================================
echo ✓ Test environment setup complete!
echo =========================================
echo.
echo To activate the environment, run:
echo   test-venv\Scripts\activate.bat
echo.
echo To run smoke tests:
echo   pytest tests\smoke\
echo.
echo To run with custom BASE_URL:
echo   set BASE_URL=https://your-url.com ^&^& pytest tests\smoke\
