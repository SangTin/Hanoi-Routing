#!/usr/bin/env bash
set -euo pipefail

if [[ "${LINE_GRAPH}" == "true" ]]; then
  if [[ -z "${ORIGINAL_GRAPH_DIR}" ]]; then
    echo "LINE_GRAPH=true requires ORIGINAL_GRAPH_DIR to be set" >&2
    exit 1
  fi
  exec hanoi_server \
    --graph-dir "${GRAPH_DIR}" \
    --original-graph-dir "${ORIGINAL_GRAPH_DIR}" \
    --query-port "${QUERY_PORT}" \
    --customize-port "${CUSTOMIZE_PORT}" \
    --log-format "${LOG_FORMAT}" \
    --line-graph
fi

exec hanoi_server \
  --graph-dir "${GRAPH_DIR}" \
  --query-port "${QUERY_PORT}" \
  --customize-port "${CUSTOMIZE_PORT}" \
  --log-format "${LOG_FORMAT}"
