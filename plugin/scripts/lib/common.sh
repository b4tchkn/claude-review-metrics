#!/usr/bin/env bash
# Common facade - sources all sub-modules
# Existing scripts that `source lib/common.sh` continue to work unchanged.

set -euo pipefail

_COMMON_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$_COMMON_LIB_DIR/constants.sh"
source "$_COMMON_LIB_DIR/tmpfile.sh"
source "$_COMMON_LIB_DIR/args.sh"
source "$_COMMON_LIB_DIR/datetime.sh"
source "$_COMMON_LIB_DIR/format.sh"
source "$_COMMON_LIB_DIR/graphql.sh"
