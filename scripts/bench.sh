#!/bin/bash
# Measures a recompiled game natively from save states: CPU time per frame,
# where that time goes, and the GPU time per frame.
# usage: scripts/bench.sh <game folder under games/> <state>... [--frames n] [--scale n] [--gpu]
set -e
here=$(cd "$(dirname "$0")/.." && pwd)
[ $# -ge 2 ] || { sed -n 2,4p "$0" | sed 's/^# //'; exit 2; }
game=$1
shift
frames=600 scale=1 gpu=0 states=()
while [ $# -gt 0 ]; do
  case "$1" in
    --frames) frames=$2; shift ;;
    --scale) scale=$2; shift ;;
    --gpu) gpu=1 ;;
    *) states+=("$(realpath "$1")") ;;
  esac
  shift
done
dir="$here/games/$game"
run="$here/build/native-$game/ps2run"
boot=$(sed -n 's/^BOOT2 *= *//p' "$dir/disc/SYSTEM.CNF" | tr -d '\r')
elf=$(ls "$dir/patched/"* 2>/dev/null | head -1)
[ -n "$elf" ] || elf="$dir/core.elf"
if [ ! -f "$elf" ]; then
  name=${boot#*\\}
  elf="$dir/disc/${name%;*}"
fi
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
cd "$dir"
for state in "${states[@]}"; do
  echo "== $(basename "$state"), $frames frames at ${scale}x"
  log="$out/run.log"
  PS2_SCALE=$scale PS2_TIME="+60,$frames" nice "$run" "$elf" --disc disc.iso --load-state "$state" --run $((frames + 61)) > "$log" 2>&1 || true
  grep -E '^\[time\]' "$log" || { tail -5 "$log"; continue; }
  start=$(sed -n 's/^\[state\] loaded frame //p' "$log")
  PS2_SCALE=$scale PS2_PROFILE="$out/cpu.prof" PS2_PROFILE_FROM=$((start + 60)) nice "$run" "$elf" --disc disc.iso --load-state "$state" --run $((frames + 61)) > /dev/null 2>&1 || true
  python3 -I "$here/scripts/profile_report.py" "$run" "$out/cpu.prof" 15
  if [ "$gpu" = 1 ]; then
    PS2_SCALE=$scale PS2_GPU_PROFILE="$((start + 60)),$((start + 60 + frames)),$out/gpu.prof" nice "$run" "$elf" --disc disc.iso --load-state "$state" --run $((frames + 61)) > /dev/null 2>&1 || true
    python3 -I "$here/scripts/gpu_profile.py" "$out/gpu.prof" 10
  fi
  echo
done
