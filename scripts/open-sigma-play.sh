#!/usr/bin/env bash
set -euo pipefail

WHISKY_CMD="/Applications/Whisky.app/Contents/Resources/WhiskyCmd"
SIGMA_DIR="/Users/alexscott/Projects/LEDctrl/sigma3000_extracted"
PLAY_EXE="Sigma Play.exe"

eval "$("$WHISKY_CMD" shellenv MessageMaker)"
cd "$SIGMA_DIR"
exec wine64 "$PLAY_EXE"
