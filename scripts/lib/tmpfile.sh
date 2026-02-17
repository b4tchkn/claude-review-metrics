#!/usr/bin/env bash
# Centralized temporary file management

_TMPFILES=()

cleanup_tmpfiles() {
  [[ ${#_TMPFILES[@]} -gt 0 ]] && rm -f "${_TMPFILES[@]}"
  return 0
}

# Set up trap once; scripts should NOT set their own EXIT trap for tmpfiles
trap cleanup_tmpfiles EXIT

# Create a tracked temporary file
make_tmpfile() {
  local f
  f=$(mktemp)
  _TMPFILES+=("$f")
  echo "$f"
}

# Register an externally-created tmpfile for cleanup
register_tmpfile() {
  _TMPFILES+=("$1")
}
