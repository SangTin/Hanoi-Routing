#!/usr/bin/env bash
set -euo pipefail

if [[ $# -eq 1 ]]; then
  INPUT_PBF="$1"
  base="$(basename "$INPUT_PBF")"
  map_name="${base%.osm.pbf}"
  if [[ "$map_name" == "$base" ]]; then
    map_name="${base%.pbf}"
  fi
  PROFILE="car"
  OUTPUT_DIR="/repo/Maps/data/${map_name}_${PROFILE}"
elif [[ $# -eq 2 ]]; then
  INPUT_PBF="$1"
  PROFILE="$2"
  base="$(basename "$INPUT_PBF")"
  map_name="${base%.osm.pbf}"
  if [[ "$map_name" == "$base" ]]; then
    map_name="${base%.pbf}"
  fi
  OUTPUT_DIR="/repo/Maps/data/${map_name}_${PROFILE}"
elif [[ $# -eq 3 ]]; then
  INPUT_PBF="$1"
  OUTPUT_DIR="$2"
  PROFILE="$3"
else
  echo "Usage: <input_pbf> [profile] | <input_pbf> <output_dir> <profile>" >&2
  echo "Examples:" >&2
  echo "  /repo/Maps/hanoi.osm.pbf" >&2
  echo "  /repo/Maps/hanoi.osm.pbf motorcycle" >&2
  echo "  /repo/Maps/hanoi.osm.pbf /repo/Maps/data/hanoi_motorcycle motorcycle" >&2
  exit 1
fi
GRAPH_DIR="$OUTPUT_DIR/graph"
REPO="/repo"

normalize_lf() {
  local file="$1"
  if [[ -f "$file" ]]; then
    sed -i 's/\r$//' "$file"
  fi
}

if [[ ! -f "$INPUT_PBF" ]]; then
  echo "Input PBF not found: $INPUT_PBF" >&2
  exit 1
fi
if [[ "$PROFILE" != "car" && "$PROFILE" != "motorcycle" ]]; then
  echo "Invalid profile: $PROFILE (expected: car|motorcycle)" >&2
  exit 1
fi

mkdir -p "$GRAPH_DIR"

# Handle Windows CRLF checkouts in mounted repos.
normalize_lf "$REPO/RoutingKit/generate_make_file"
normalize_lf "$REPO/rust_road_router/flow_cutter_cch_order.sh"
normalize_lf "$REPO/rust_road_router/flow_cutter_cch_cut_order.sh"
normalize_lf "$REPO/rust_road_router/flow_cutter_cch_cut_reorder.sh"

# Build C++ tools inside mounted repo
(
  cd "$REPO/RoutingKit"
  ./generate_make_file
  make -j"$(nproc)"
)

cmake -S "$REPO/CCH-Generator" -B "$REPO/CCH-Generator/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_RUNTIME_OUTPUT_DIRECTORY="$REPO/CCH-Generator/lib"
cmake --build "$REPO/CCH-Generator/build" -j"$(nproc)"

# Build InertialFlowCutter console required by flow_cutter_* scripts.
IFC_BUILD_DIR="$REPO/rust_road_router/lib/InertialFlowCutter/build"
mkdir -p "$IFC_BUILD_DIR"
(
  cd "$IFC_BUILD_DIR"
  cmake -DCMAKE_BUILD_TYPE=Release -DUSE_KAHIP=OFF ..
  make -j"$(nproc)" console
)

# Build generate_line_graph from a temporary copy so compatibility patches
# never modify the mounted host repository.
TMP_WORK="$(mktemp -d /tmp/hanoi-preprocess-XXXXXX)"
trap 'rm -rf "$TMP_WORK"' EXIT

cp -a "$REPO/CCH-Hanoi" "$TMP_WORK/CCH-Hanoi"
cp -a "$REPO/rust_road_router" "$TMP_WORK/rust_road_router"

sed -i 's/is_multiple_of(&align_of::<T>())/is_multiple_of(align_of::<T>())/' \
  "$TMP_WORK/rust_road_router/engine/src/util.rs" || true

for i in 1 2 3 4 5; do
  if CARGO_NET_RETRY=20 \
     CARGO_HTTP_TIMEOUT=600 \
     CARGO_REGISTRIES_CRATES_IO_PROTOCOL=sparse \
     cargo +nightly build --release \
       --manifest-path "$TMP_WORK/CCH-Hanoi/Cargo.toml" \
       -p hanoi-tools \
       --bin generate_line_graph; then
    break
  fi
  if [[ "$i" -eq 5 ]]; then
    echo "cargo build failed after retries" >&2
    exit 1
  fi
  sleep 5
done

CCH_GEN="$REPO/CCH-Generator/lib/cch_generator"
VALIDATOR="$REPO/CCH-Generator/lib/validate_graph"
COND_EXTRACT="$REPO/RoutingKit/bin/conditional_turn_extract"
LINE_GRAPH_GEN="$TMP_WORK/CCH-Hanoi/target/release/generate_line_graph"

"$CCH_GEN" "$INPUT_PBF" "$GRAPH_DIR" --profile "$PROFILE"
"$VALIDATOR" "$GRAPH_DIR"

"$COND_EXTRACT" "$INPUT_PBF" "$GRAPH_DIR" "$OUTPUT_DIR" --profile "$PROFILE"
"$VALIDATOR" "$GRAPH_DIR"

"$LINE_GRAPH_GEN" "$GRAPH_DIR" "$OUTPUT_DIR/line_graph"
"$VALIDATOR" "$GRAPH_DIR" --turn-expanded "$OUTPUT_DIR/line_graph"

"$REPO/rust_road_router/flow_cutter_cch_order.sh" "$GRAPH_DIR"
"$REPO/rust_road_router/flow_cutter_cch_cut_order.sh" "$GRAPH_DIR"
"$REPO/rust_road_router/flow_cutter_cch_cut_reorder.sh" "$GRAPH_DIR"
"$REPO/rust_road_router/flow_cutter_cch_order.sh" "$OUTPUT_DIR/line_graph"

echo "Preprocess complete: $OUTPUT_DIR"
