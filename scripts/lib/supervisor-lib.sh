# Pure decision functions. Sourced by supervisor.sh and by tests.
# No side effects, no external commands, all inputs as arguments.

compute_slept() { # now last_tick tick_seconds
  local now="$1" last="$2" tick="$3"
  if [[ "$last" -gt 0 && $(( now - last )) -gt $(( tick * 2 )) ]]; then
    echo 1
  else
    echo 0
  fi
}

classify_state() { # tmux_present alive_epoch now liveness_stale grace_until
  local tmux_present="$1" alive="$2" now="$3" stale="$4" grace_until="$5"
  if [[ "$tmux_present" -eq 0 ]]; then echo "DOWN"; return; fi
  if [[ "$now" -lt "$grace_until" ]]; then echo "GRACE"; return; fi
  if [[ $(( now - alive )) -gt "$stale" ]]; then echo "DOWN"; return; fi
  echo "HEALTHY"
}

_count_within() { # csv now window  -> prints count of epochs e with (now-e) <= window
  local csv="$1" now="$2" win="$3" c=0 e
  [[ -z "$csv" ]] && { echo 0; return; }
  IFS=',' read -ra _arr <<< "$csv"
  for e in "${_arr[@]+"${_arr[@]}"}"; do
    [[ -z "$e" ]] && continue
    if [[ $(( now - e )) -le "$win" ]]; then c=$(( c + 1 )); fi
  done
  echo "$c"
}

flap_decision() { # restarts_csv now flap_count flap_window path_count path_window backoff_csv
  local csv="$1" now="$2" fc="$3" fw="$4" pc="$5" pw="$6" bcsv="$7"
  local pcount fcount
  pcount="$(_count_within "$csv" "$now" "$pw")"
  if [[ "$pcount" -ge "$pc" ]]; then echo "PATHOLOGICAL"; return; fi
  fcount="$(_count_within "$csv" "$now" "$fw")"
  if [[ "$fcount" -ge "$fc" ]]; then
    local -a barr; IFS=',' read -ra barr <<< "$bcsv"
    local idx=$(( fcount - fc ))
    local max=$(( ${#barr[@]} - 1 ))
    [[ $idx -gt $max ]] && idx=$max
    [[ $idx -lt 0 ]] && idx=0
    echo "BACKOFF:${barr[$idx]}"
    return
  fi
  echo "OK"
}

should_rotate() { # size max_bytes
  if [[ "$1" -gt "$2" ]]; then echo 1; else echo 0; fi
}
