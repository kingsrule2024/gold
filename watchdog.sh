#!/bin/bash
# ==============================
# Get GPU worker name
# ==============================
GPU_INFO=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1)
GPU_MODEL=$(echo "$GPU_INFO" | sed -E 's/^(NVIDIA |nvidia )//; s/(GeForce |geforce )//; s/(RTX |rtx )//; s/[Ss][Uu][Pp][Ee][Rr]/S/; s/ //g')
ORDER_NUM=$(hostname)
WORKERNAME="${GPU_MODEL}_${ORDER_NUM}"
echo "🎮 GPU worker name: $WORKERNAME"

# ==============================
# Config
# ==============================
APP="/root/gpuminer"   # full path to miner binary
# Append workername to wallet
WALLET="3KFyMUee6eD3GhYPqQZ2bnax7ByDwpffEjPmkKBWkaK3WQU2joghU1nQBrjEVRkJvGo4BFR1PgtMpSiuFSr4FwqwMZQbNePkHVwFu7R5PCyMz5LfrceGF6gBQ6Wvdfby8A3P"
ARGS="--pubkey $WALLET --name=$(hostname) --label=Rental"
CHECK_INTERVAL=5                # seconds between checks
LOGFILE="/root/gpuminer_watchdog.log"

# ==============================
# Loop
# ==============================
echo "[WATCHDOG] Starting watchdog for GPU miner..."
while true; do
    if pgrep -x "$(basename "$APP")" > /dev/null; then
        echo "[WATCHDOG] Miner is running." | tee -a "$LOGFILE"
    else
        echo "[WATCHDOG] Miner not running. Starting..." | tee -a "$LOGFILE"
        $APP $ARGS &
    fi
    sleep $CHECK_INTERVAL
done