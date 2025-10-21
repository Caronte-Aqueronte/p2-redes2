#!/usr/bin/env bash
set -u

IF_A="enx9c69d30f13c0"   # primaria
IF_B="enx9c69d30f132d"   # secundaria
INIT_A="./initr.sh"
INIT_B="./initr2.sh"
LOGTAG="[link-watch]"

get_state() {
  cat "/sys/class/net/$1/operstate" 2>/dev/null || echo "unknown"
}

run_safe() {
  local cmd="$1"
  if ! bash -c "$cmd"; then
    echo "$LOGTAG aviso: '$cmd' devolvió error pero sigo corriendo"
  fi
}

apply_by_policy() {
  local sa="$1" sb="$2"
  if [[ "$sa" == "up" && "$sb" == "up" ]]; then
    echo "$LOGTAG ambas up → initr.sh"
    run_safe "$INIT_A"
  elif [[ "$sa" != "up" && "$sb" == "up" ]]; then
    echo "$LOGTAG $IF_A down / $IF_B up → initr2.sh"
    run_safe "$INIT_B"
  elif [[ "$sa" == "up" && "$sb" != "up" ]]; then
    echo "$LOGTAG $IF_B down / $IF_A up → initr.sh"
    run_safe "$INIT_A"
  else
    echo "$LOGTAG ninguna up → no cambio de rutas"
  fi
}

LAST_A="$(get_state "$IF_A")"
LAST_B="$(get_state "$IF_B")"
echo "$LOGTAG estado inicial: $IF_A=$LAST_A, $IF_B=$LAST_B"
apply_by_policy "$LAST_A" "$LAST_B"

while true; do
  sleep 1
  A="$(get_state "$IF_A")"
  B="$(get_state "$IF_B")"
  if [[ "$A" != "$LAST_A" || "$B" != "$LAST_B" ]]; then
    echo "$LOGTAG cambio: $IF_A=$A, $IF_B=$B"
    apply_by_policy "$A" "$B"
    LAST_A="$A"; LAST_B="$B"
  fi
done
