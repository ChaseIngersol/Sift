#!/usr/bin/env bash
# Generate Core/WeightsData.lua from SimulationCraft's maintained profiles.
# Build-time only; nothing here runs inside the game.
#
# Usage: tools/gen-weights/gen-weights.sh <simc-checkout> [iterations]
#
#   <simc-checkout>  a clone of github.com/simulationcraft/simc on the branch
#                    for the live patch, built with:
#                      cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DBUILD_GUI=OFF
#                      cmake --build build -j
#   [iterations]     per sim, default 10000. Scale factors run one sim per
#                    stat, so a profile costs about ten sims.
#
# Output lands in tools/gen-weights/out/ (raw reports, ignored by git) and
# Core/WeightsData.lua (committed, with provenance in its header).
set -euo pipefail

SIMC_DIR=${1:?usage: gen-weights.sh <simc-checkout> [iterations]}
ITER=${2:-10000}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
SIMC="$SIMC_DIR/build/simc"
SEASON=${SEASON:-MID2}
OUT="$HERE/out"
THREADS=${THREADS:-$(nproc)}
STATS=strength,agility,intellect,stamina,crit,haste,mastery,versatility,weapon_dps,weapon_offhand_dps,armor,leech,avoidance,speed

[ -x "$SIMC" ] || { echo "no simc binary at $SIMC" >&2; exit 1; }
mkdir -p "$OUT"
rm -f "$OUT"/*.json "$OUT"/*.txt "$OUT"/*.log

count=0
for f in "$SIMC_DIR"/profiles/"$SEASON"/*.simc; do
  name=$(basename "$f" .simc)
  count=$((count + 1))
  printf '%s\n' "[$count] $name"
  "$SIMC" "$f" \
    calculate_scale_factors=1 scale_only="$STATS" scale_over=dps \
    iterations="$ITER" threads="$THREADS" \
    html= output="$OUT/$name.txt" json2="$OUT/$name.json" \
    > "$OUT/$name.log" 2>&1 || { echo "  simc failed, see $OUT/$name.log" >&2; }
done

python3 "$HERE/scale-to-lua.py" "$SIMC_DIR" "$OUT" "$ROOT/Core/WeightsData.lua" "$ITER" "$SEASON"
