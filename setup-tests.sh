#!/bin/bash
# Setup script for Circle of Trust test environment

set -e

echo "========================================="
echo "Circle of Trust - Test Environment Setup"
echo "========================================="

# Check if Python 3 is available
if ! command -v python3 &> /dev/null; then
    echo "ERROR: Python 3 is not installed"
    exit 1
fi

echo "✓ Python 3 found: $(python3 --version)"

# Create virtual environment
echo ""
echo "Creating virtual environment..."
if [ -d "test-venv" ]; then
    echo "  Removing existing test-venv..."
    rm -rf test-venv
fi

python3 -m venv test-venv
echo "✓ Virtual environment created"

# Activate virtual environment
echo ""
echo "Activating virtual environment..."
source test-venv/Scripts/activate || source test-venv/bin/activate

# Upgrade pip
echo ""
echo "Upgrading pip..."
pip install --quiet --upgrade pip

# Install test dependencies
echo ""
echo "Installing test dependencies..."
pip install --quiet -r tests/requirements.txt
echo "✓ Dependencies installed"

# Verify installation
echo ""
echo "Verifying installation..."
python -m pytest --version
echo "✓ pytest installed successfully"

# Test collection
echo ""
echo "Collecting tests..."
python -m pytest tests/smoke/test_smoke.py --collect-only -q

echo ""
echo "========================================="
echo "✓ Test environment setup complete!"
echo "========================================="
echo ""
echo "To activate the environment, run:"
echo "  source test-venv/Scripts/activate  (Windows)"
echo "  source test-venv/bin/activate      (Linux/Mac)"
echo ""
echo "To run smoke tests:"
echo "  pytest tests/smoke/"
echo ""
echo "To run with custom BASE_URL:"
echo "  BASE_URL=https://your-url.com pytest tests/smoke/"
