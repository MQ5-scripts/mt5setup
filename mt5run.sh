#!/usr/bin/env bash
# mt5run.sh — Launch MetaTrader 5 using Wine with a separate Wine prefix

WINEPREFIX="$HOME/.mt5"
MT5_PATH="$WINEPREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe"

if [ ! -f "$MT5_PATH" ]; then
  echo "Error: MetaTrader 5 not found at:"
  echo "  $MT5_PATH"
  echo "Please ensure it is installed correctly."
  exit 1
fi

wine "$MT5_PATH"