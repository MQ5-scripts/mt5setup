#!/usr/bin/env bash
set -e  # exit on error

URL="https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe"
URL_WEBVIEW="https://msedge.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/c1336fd6-a2eb-4669-9b03-949fc70ace0e/MicrosoftEdgeWebview2Setup.exe"
WINE_VERSION="stable"

sudo rm -f /etc/apt/sources.list.d/winehq*

sudo apt update
sudo apt upgrade -y
sudo apt install -y software-properties-common wget gnupg2 ca-certificates bc

sudo dpkg --add-architecture i386
sudo mkdir -pm755 /etc/apt/keyrings
sudo wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key

OS_VER=$(lsb_release -r | cut -f2)
OS_VER_100=$(echo "$OS_VER * 100" | bc -l | cut -d "." -f1)

if (( $OS_VER_100 >= 2410 )); then
  sudo wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/ubuntu/dists/oracular/winehq-oracular.sources
elif (( $OS_VER_100 < 2410 )) && (( $OS_VER_100 >= 2400 )); then
  sudo wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/ubuntu/dists/noble/winehq-noble.sources
fi

sudo apt update
sudo apt install -y --install-recommends winehq-$WINE_VERSION
sudo apt install -y winetricks

mkdir -p ~/mt5install && cd "$_"
wget "$URL" -O mt5setup.exe || { echo "Failed to download MetaTrader"; exit 1; }
wget "$URL_WEBVIEW" -O MicrosoftEdgeWebview2Setup.exe || { echo "Failed to download WebView2"; exit 1; }

if ! command -v wine &> /dev/null; then
    echo "Wine installation failed or wine is not in PATH"
    exit 1
fi

export WINEPREFIX=~/.mt5
# export WINEARCH=win32

wineboot --init
sleep 5
winetricks win10

wine MicrosoftEdgeWebview2Setup.exe /silent /install || echo "Warning: WebView2 may not have installed correctly."
if [ -f "$WINEPREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe" ]; then
  echo "MetaTrader 5 is already installed, skipping setup..."
else
  wine mt5setup.exe || { echo "MetaTrader 5 installation failed"; exit 1; }
fi

wine "$WINEPREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe" &

wine_pid=$!
wait $wine_pid
timeout 60 wineserver -w || echo "Warning: Wine did not exit cleanly within 60 seconds."