#!/usr/bin/env bash
set -uo pipefail
shopt -s nullglob
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0
for t in "${DIR}"/test_*.sh; do
  echo "== ${t##*/} =="
  if bash "$t"; then :; else fail=1; fi
done
[[ $fail -eq 0 ]] && echo "ALL GREEN" || { echo "SOME RED"; exit 1; }
