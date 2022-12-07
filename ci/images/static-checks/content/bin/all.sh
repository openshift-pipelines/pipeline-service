#!/usr/bin/env bash

# Copyright 2022 The Pipeline Service Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(
  cd "$(dirname "$0")" >/dev/null
  pwd
)"
PROJECT_DIR="$(
  cd "$SCRIPT_DIR/../.." >/dev/null || exit 1
  pwd
)"
export PROJECT_DIR

usage() {
  echo "
Usage:
    ${0##*/} [options]

Run the static checks on the project.

Optional arguments:
    -w, --workspace_dir WORKSPACE_DIR.
        Workspace directory.
        Default: $PROJECT_DIR
    -d, --debug
        Activate tracing/debug mode.
    -h, --help
        Display this message.

Example:
    ${0##*/}
" >&2
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
    -w | --workspace_dir)
      shift
      WORKSPACE_DIR="$1"
      ;;
    -d | --debug)
      set -x
      DEBUG="--debug"
      export DEBUG
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "[ERROR] Unknown argument: $1" >&2
      usage
      exit 1
      ;;
    esac
    shift
  done
}

run_checks() {
  FAILED=()
  mapfile -t check_list < <(
    find "$SCRIPT_DIR" -name \*.sh -exec basename {} \; |
    grep -vE "^all.sh$" |
    sort
  )
  for check in "${check_list[@]}"; do
    check_name=${check::-3}
    echo "[$check_name]"
    if ! "$SCRIPT_DIR/$check" --workspace_dir "$WORKSPACE_DIR"; then
      FAILED+=("$check_name")
    fi
    echo
  done
}

main() {
  if [ -n "${DEBUG:-}" ]; then
    set -x
  fi
  parse_args "$@"
  run_checks
  if [ -n "${FAILED[*]}" ]; then
    echo "[ERROR] Test failed: ${FAILED[*]}" >&2
    exit 1
  fi
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi
