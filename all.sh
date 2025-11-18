#!/bin/bash

set -e  ye

if ! command -v screen &>/dev/null; then
    sudo apt update && sudo apt install -y screen
fi

screen -ls | grep gensyn | awk '{print $1}' | cut -d. -f1 | while read id; do screen -S "$id" -X quit; done

screen -dmS gensyn bash -c 'bash <(curl -fsSL https://raw.githubusercontent.com/Karanfan47/gen/main/old.sh)'

sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/HustleAirdrops/Pipe-mainnet-node/main/s.sh)"

echo "✅ Setup complete! Ab app vps close kr skti h☺️"

