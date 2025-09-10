#!/bin/bash

set -e  ye

bash <(curl -fsSL https://github.com/HustleAirdrops/Aztec-One-Command-Installation-Run/raw/main/s.sh)

bash <(curl -fsSL https://raw.githubusercontent.com/Karanfan47/special-special/main/import.sh)

if ! command -v screen &>/dev/null; then
    sudo apt update && sudo apt install -y screen
fi

screen -S gensyn bash -c 'bash <(curl -fsSL https://raw.githubusercontent.com/HustleAirdrops/Gensyn-Advanced-Solutions/main/s.sh)'
