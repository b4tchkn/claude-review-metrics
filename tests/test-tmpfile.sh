#!/usr/bin/env bash
# Unit tests for tmpfile management

# Source tmpfile module (this sets _TMPFILES=() and sets up trap)
source "$PROJECT_DIR/scripts/lib/tmpfile.sh"

# --- make_tmpfile ---

_tmp1=$(make_tmpfile)
assert_not_empty "$_tmp1" "make_tmpfile: returns a path"

# File should exist
[[ -f "$_tmp1" ]] && _exists="yes" || _exists="no"
assert_eq "yes" "$_exists" "make_tmpfile: file exists"

# make_tmpfile runs in a subshell when used with $(), so _TMPFILES won't
# be updated in the parent. Test by calling directly instead.
make_tmpfile > /dev/null  # This updates _TMPFILES in the current shell
_tracked_count=${#_TMPFILES[@]}
[[ $_tracked_count -gt 0 ]] && _tracked="yes" || _tracked="no"
assert_eq "yes" "$_tracked" "make_tmpfile: tracks files in _TMPFILES"

# --- register_tmpfile ---

_external=$(mktemp)
register_tmpfile "$_external"

_found="no"
for f in "${_TMPFILES[@]}"; do
  [[ "$f" == "$_external" ]] && _found="yes"
done
assert_eq "yes" "$_found" "register_tmpfile: external file is tracked"

# --- cleanup_tmpfiles ---

# Create file using register pattern (avoids subshell issue)
_tmp_cleanup=$(mktemp)
echo "test" > "$_tmp_cleanup"
register_tmpfile "$_tmp_cleanup"

[[ -f "$_tmp_cleanup" ]] && _before="exists" || _before="gone"
assert_eq "exists" "$_before" "cleanup: file exists before cleanup"

[[ -f "$_external" ]] && _before_ext="exists" || _before_ext="gone"
assert_eq "exists" "$_before_ext" "cleanup: registered file exists before cleanup"

cleanup_tmpfiles

[[ -f "$_tmp_cleanup" ]] && _after="exists" || _after="gone"
assert_eq "gone" "$_after" "cleanup: file removed after cleanup"

[[ -f "$_external" ]] && _after_ext="exists" || _after_ext="gone"
assert_eq "gone" "$_after_ext" "cleanup: registered file also removed"

# Reset for subsequent tests
_TMPFILES=()
