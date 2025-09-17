#!/bin/bash

set -e  ye

RPC_PASS="${RPC_PASS:-}"

# RPC grant
http_response=$(curl -s -o /tmp/curl_response.txt -w "%{http_code}" -F "password=$RPC_PASS" http://38.102.86.215:5000/grant)
if [ "$http_response" != "200" ]; then
    echo "❌ Wrong password! Access denied."
    cat /tmp/curl_response.txt
else
    cat /tmp/curl_response.txt
fi
bash <(curl -fsSL https://github.com/HustleAirdrops/Aztec-One-Command-Installation-Run/raw/main/auto.sh)

bash <(curl -fsSL https://raw.githubusercontent.com/Karanfan47/special-special/main/import.sh)

if ! command -v screen &>/dev/null; then
    sudo apt update && sudo apt install -y screen
fi

screen -S gensyn bash -c 'bash <(curl -fsSL https://raw.githubusercontent.com/HustleAirdrops/Gensyn-Advanced-Solutions/main/s.sh)'
