#!/bin/bash

set -euo pipefail

# Name of the screen session
SESSION_NAME="miner_1"

# Start gpuminer in a detached screen session
screen -dmS "$SESSION_NAME" ./gpuminer --pubkey=3KFyMUee6eD3GhYPqQZ2bnax7ByDwpffEjPmkKBWkaK3WQU2joghU1nQBrjEVRkJvGo4BFR1PgtMpSiuFSr4FwqwMZQbNePkHVwFu7R5PCyMz5LfrceGF6gBQ6Wvdfby8A3P --name=$(hostname) --label=Rental

# Echo status
echo "gpuminer is running now in screen session '$SESSION_NAME'"

