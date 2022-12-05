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
  cd "$SCRIPT_DIR/../../.." >/dev/null || exit 1
  pwd
)"
export PROJECT_DIR

usage() {
  echo "
Usage:
    ${0##*/} [options]

Upgrade Pipeline Service dependencies.

Optional arguments:
    -t, --task TASKNAME
        Only run the selected task. Can be repeated to run multiple tasks.
        TASKNAME must be in [$(echo "${DEFAULT_TASKS[@]}" | sed 's: :, :')].
    -d, --debug
        Activate tracing/debug mode.
    -h, --help
        Display this message.

Example:
    ${0##*/} --task update_dockerfiles_base_images
" >&2
}

parse_args() {
  mapfile -t DEFAULT_TASKS < <(find "$SCRIPT_DIR/tasks" -type f -name \*.sh -exec basename {} \; | sed 's:...$::')
  TASKS=()
  while [[ $# -gt 0 ]]; do
    case $1 in
    -t | --task)
      shift
      TASKS+=("$1")
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
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
    esac
    shift
  done
}

init() {
  if [ -z "${TASKS[*]}" ]; then
    TASKS=( "${DEFAULT_TASKS[@]}" )
  fi
  COMMIT_MSG="${TMPDIR:-/tmp}/update_commit_msg.txt"
  export COMMIT_MSG
  if [ -e "$COMMIT_MSG" ]; then
    rm -f "$COMMIT_MSG"
  fi
}

main() {
  if [ -n "${DEBUG:-}" ]; then
    set -x
  fi
  parse_args "$@"
  init
  for task_name in "${TASKS[@]}"; do
    echo "[$task_name]"
    "$SCRIPT_DIR/tasks/$task_name.sh"
    echo
  done
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi
