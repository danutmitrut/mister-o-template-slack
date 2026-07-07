# Sourced, not executed. Minimal assertion harness for bash scripts.
# No 'set -e' here; the sourcing test controls that.

_T_PASS=0
_T_FAIL=0

t_fail() { _T_FAIL=$((_T_FAIL + 1)); echo "  FAIL: $1"; return 1; }
t_pass() { _T_PASS=$((_T_PASS + 1)); echo "  ok:   $1"; }

assert_eq() { # expected actual msg
  if [[ "$1" == "$2" ]]; then t_pass "$3"; else t_fail "$3 (expected='$1' actual='$2')"; fi
}

assert_contains() { # haystack needle msg
  if [[ "$1" == *"$2"* ]]; then t_pass "$3"; else t_fail "$3 (no '$2' in '$1')"; fi
}

assert_not_contains() { # haystack needle msg
  if [[ "$1" != *"$2"* ]]; then t_pass "$3"; else t_fail "$3 (found '$2' in '$1')"; fi
}

assert_rc() { # expected_rc msg cmd...
  local exp="$1" msg="$2"; shift 2
  local rc=0; "$@" >/dev/null 2>&1 || rc=$?
  if [[ "$rc" == "$exp" ]]; then t_pass "$msg"; else t_fail "$msg (expected rc=$exp got $rc)"; fi
}

assert_file_contains() { # file needle msg
  if [[ -f "$1" ]] && grep -qF -- "$2" "$1"; then t_pass "$3"; else t_fail "$3 (file '$1' lacks '$2')"; fi
}

t_summary() {
  echo "----"
  echo "PASS=${_T_PASS} FAIL=${_T_FAIL}"
  [[ ${_T_FAIL} -eq 0 ]]
}
