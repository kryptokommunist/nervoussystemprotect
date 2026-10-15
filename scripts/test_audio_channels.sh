#!/bin/bash
set -e

# ==============================================================================
# nervoussystemprotect - Complete Audio Channels & Routing Verification Script
# ==============================================================================
# This script runs the end-to-end routing diagnostics for all offered channels:
# 1. Physical Microphone with acoustic speaker emission test
# 2. BlackHole 2ch virtual loopback
# 3. MacBook Pro Speakers process tap (intercepting speaker-bound audio)
# 4. Global System Audio tap
# 5. Microsoft Teams Audio loopback (if installed)
# 6. AudioController neural pipeline with live microphone
# 7. Idiot-safe auto-start on device assignment
# 8. Real-time DSP controls (pitch, warmth filter, mix, volume, bypass)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_DIR}"

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

echo "===================================================================="
echo " Starting nervoussystemprotect Audio Channels Verification Suite"
echo " Timestamp: $(date)"
echo " Git Commit: $(git rev-parse --short HEAD 2>/dev/null || echo 'N/A')"
echo " Git Branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'N/A')"
echo "===================================================================="

# Check if application bundle or debug binary should be tested
if [ -f "./nervoussystemprotect.app/Contents/MacOS/nervoussystemprotect" ]; then
    echo "==> Running verification on packaged application bundle..."
    ./nervoussystemprotect.app/Contents/MacOS/nervoussystemprotect --test-all-channels
else
    echo "==> Running verification via Swift Package Manager..."
    swift run nervoussystemprotect --test-all-channels
fi

echo ""
echo "===================================================================="
echo " ✅ SUCCESS: All offered audio channels verified and guaranteed!"
echo "===================================================================="
