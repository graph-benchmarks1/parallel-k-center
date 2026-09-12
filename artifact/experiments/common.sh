#!/usr/bin/env bash
set -euo pipefail

experiment_die() {
  echo "ERROR: $*" >&2
  exit 2
}

csv_to_array() {
  local value="$1"
  local target="$2"
  local old_ifs="${IFS}"
  IFS=','
  read -r -a "${target}" <<< "${value}"
  IFS="${old_ifs}"
}

graph_n_from_adj() {
  local graph="$1"
  awk '
    NR == 1 && $1 ~ /^[0-9]+$/ { print $1; exit }
    NR == 2 && $1 ~ /^[0-9]+$/ { print $1; exit }
  ' "${graph}"
}


resolve_k_token() {
  local token="$1"
  local graph="$2"

  case "${token}" in
    sqrt_n)
      local n
      n="$(graph_n_from_adj "${graph}")"
      [[ -n "${n}" && "${n}" != "0" ]] || return 1
      # k is integral.  Interpret sqrt(n) as floor(sqrt(n)).
      awk -v n="${n}" 'BEGIN { printf "%d", sqrt(n) }'
      ;;
    *)
      printf '%s' "${token}"
      ;;
  esac
}

resolve_rpp_token() {
  local token="$1"
  local graph="$2"

  case "${token}" in
    log2n|1log2n|2log2n|3log2n|4log2n)
      local n factor
      n="$(graph_n_from_adj "${graph}")"
      [[ -n "${n}" && "${n}" != "0" ]] || return 1
      case "${token}" in
        log2n|1log2n) factor=1 ;;
        *) factor="${token%log2n}" ;;
      esac
      awk -v n="${n}" -v f="${factor}" 'BEGIN { printf "%.12g", f * log(n)/log(2) }'
      ;;
    *)
      printf '%s' "${token}"
      ;;
  esac
}

extract_scalar_eq() {
  local key="$1"
  local file="$2"
  grep -E "^[[:space:]]*${key}[[:space:]]*=" "${file}" \
    | tail -n1 \
    | sed -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//" || true
}

extract_runtime() {
  local file="$1"
  grep -Eo '^[[:space:]]*### Running Time:[[:space:]]*[0-9.eE+-]+' "${file}" \
    | tail -n1 | awk '{print $NF}' || true
}

algorithm_binary() {
  case "$1" in
    gonzalez) printf 'gonzalez' ;;
    approximategonzalez) printf 'approximategonzalez' ;;
    abboud) printf 'abboud' ;;
    thorupsimple) printf 'thorupsimple' ;;
    *) return 1 ;;
  esac
}
