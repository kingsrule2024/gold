#!/bin/bash
# Load environment
source /etc/profile
[ -f ~/.bashrc ] && source ~/.bashrc

cd /root/ || exit 1

set -euo pipefail

# ==============================
# Requirements
# ==============================
require() {
  command -v "$1" >/dev/null 2>&1 || { echo "Error: '$1' not found. Please install it."; exit 1; }
}

require screen
require lscpu

# ==============================
# Cleanup old miner sessions
# ==============================
echo "Cleaning up old miner_* screen sessions…"
# List miner sessions, including dead ones
OLD_SESSIONS=$(screen -ls | awk '/miner_/ {print $1}' || true)

if [[ -n "$OLD_SESSIONS" ]]; then
  for s in $OLD_SESSIONS; do
    echo "Attempting to kill $s"
    screen -S "$s" -X quit || true
  done
fi

# Remove dead screens so they don't block new sessions
screen -wipe >/dev/null || true

# ==============================
# Detect system info
# ==============================
TOTAL_THREADS=$(nproc)
NUM_INSTANCES=$(( TOTAL_THREADS / 4 ))  # 4 threads per instance
NUMA_COUNT=$(lscpu | awk '/NUMA node\(s\):/ {print $3}')
NUMA_COUNT=${NUMA_COUNT:-1}

echo "Detected $TOTAL_THREADS threads across $NUMA_COUNT NUMA node(s)."
echo "Launching $NUM_INSTANCES instances (4 threads each)..."

# ==============================
# Build per-node CPU pairs
# ==============================
declare -A NODE_PAIRS

build_node_pairs() {
  local node="$1"
  mapfile -t rows < <(lscpu -e=CPU,CORE,NODE | awk -v node="$node" 'NR>1 && $3==node {print $1" "$2}' | sort -k2,2n -k1,1n)

  local current_core="" pair="" out=()
  for line in "${rows[@]}"; do
    cpu="${line%% *}"; core="${line##* }"
    if [[ "$core" != "$current_core" && -n "$pair" ]]; then
      out+=("$pair"); pair=""
    fi
    current_core="$core"
    if [[ -z "$pair" ]]; then
      pair="$cpu"
    else
      pair="$pair,$cpu"
    fi
  done
  [[ -n "$pair" ]] && out+=("$pair")
  NODE_PAIRS[$node]="${out[*]}"
}

for n in $(seq 0 $((NUMA_COUNT-1))); do
  build_node_pairs "$n"
done

split_to_array() {
  local s="$1"; shift
  eval "$1=( \$s )"
}

# ==============================
# Worker name
# ==============================
CPU_FULL_MODEL=$(lscpu | grep "Model name:" | awk -F: '{print $2}' | xargs)
if echo "$CPU_FULL_MODEL" | grep -iq "sample"; then
    CPU_MODEL="sample"
else
    CPU_MODEL=$(echo "$CPU_FULL_MODEL" | grep -oE "[0-9]{4,5}[A-Za-z0-9]*|7K[0-9]{2}" | head -n1 | tr '[:upper:]' '[:upper:]')
fi
ORDER_NUM=$(hostname)
WORKERNAME="${CPU_MODEL}_${ORDER_NUM}"
echo "🖥️ CPU worker name: $WORKERNAME"

# ==============================
# Miner command template
# ==============================
MINER_CMD="./gpuminer --pubkey=3KFyMUee6eD3GhYPqQZ2bnax7ByDwpffEjPmkKBWkaK3WQU2joghU1nQBrjEVRkJvGo4BFR1PgtMpSiuFSr4FwqwMZQbNePkHVwFu7R5PCyMz5LfrceGF6gBQ6Wvdfby8A3P --name=$(hostname) --label=Rental"

# ==============================
# Instances per NUMA node
# ==============================
declare -A INST_PER_NODE
base=$(( NUM_INSTANCES / NUMA_COUNT ))
rem=$(( NUM_INSTANCES % NUMA_COUNT ))
for n in $(seq 0 $((NUMA_COUNT-1))); do
  add=0
  (( n < rem )) && add=1
  INST_PER_NODE[$n]=$(( base + add ))
done

# ==============================
# Launch instances
# ==============================
SESSION_ID=1
for n in $(seq 0 $((NUMA_COUNT-1))); do
  split_to_array "${NODE_PAIRS[$n]}" pairs
  num_pairs=${#pairs[@]}
  [[ ${INST_PER_NODE[$n]} -eq 0 ]] && continue

  local_inst=${INST_PER_NODE[$n]}
  pbase=$(( num_pairs / local_inst ))
  prem=$(( num_pairs % local_inst ))
  [[ $pbase -eq 0 ]] && pbase=1

  idx=0
  for i in $(seq 1 $local_inst); do
    take=$pbase
    (( i <= prem )) && take=$((take+1))

    CPUSET=""
    for _ in $(seq 1 $take); do
      [[ $idx -lt $num_pairs ]] || break
      [[ -n "$CPUSET" ]] && CPUSET+=","
      CPUSET+="${pairs[$idx]}"
      idx=$((idx+1))
    done

    # Fallback if empty
    [[ -z "$CPUSET" ]] && CPUSET=$(lscpu -e=CPU,NODE | awk -v node="$n" 'NR>1 && $2==node {print $1; exit}')

    SESSION="miner_${SESSION_ID}"
    echo "-> Node $n | $SESSION | CPUs {$CPUSET} | Workername: $WORKERNAME"

    if command -v numactl >/dev/null 2>&1; then
      screen -dmS "$SESSION" bash -lc "numactl --cpunodebind=$n --membind=$n taskset -c $CPUSET $MINER_CMD || taskset -c $CPUSET $MINER_CMD"
    else
      screen -dmS "$SESSION" bash -lc "taskset -c $CPUSET $MINER_CMD"
    fi

    SESSION_ID=$((SESSION_ID+1))
  done
done

echo "All $NUM_INSTANCES instances launched."
echo "List sessions:  screen -ls"
echo "Attach:         screen -r miner_1"
