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
  cd "$SCRIPT_DIR/../../../../.." >/dev/null || exit 1
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
        Default: None
    -w, --workspace_dir WORKSPACE_DIR.
        Workspace directory.
        Default: $PROJECT_DIR
    -d, --debug
        Activate tracing/debug mode.
    -h, --help
        Display this message.

Example:
    ${0##*/} --task update_dockerfiles_base_images_sha
" >&2
}

parse_args() {
  mapfile -t DEFAULT_TASKS < <(find "$SCRIPT_DIR/tasks" -type f -name \*.sh -exec basename {} \; | sort | sed 's:...$::')
  TASKS=()
  WORKSPACE_DIR="$PROJECT_DIR"
  while [[ $# -gt 0 ]]; do
    case $1 in
    -t | --task)
      shift
      TASKS+=("$1")
      ;;
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
  export WORKSPACE_DIR
  cd "$WORKSPACE_DIR"
  git config --global --add safe.directory "$PWD"
}

prepare_branch(){
  # Revert any change to the current branch
  if ! git diff --quiet; then
    git stash --include-untracked
    GIT_STASH="true"
  fi
  GIT_STASH=${GIT_STASH:-}
  START_COMMIT=$(git rev-parse HEAD)
}

show_summary(){
  local updated="false"
  if ! git diff --quiet $START_COMMIT..HEAD; then
      updated="true"
  fi

  echo
  echo "[Summary]"
  if [ "$updated" = "true" ]; then
    git log --format="%B" "$START_COMMIT..HEAD"
  else
    echo "No updates"
  fi
}

revert_branch(){
  echo
  git clean --force -x
  if [ -n "$GIT_STASH" ]; then
    git stash pop
  fi
}

main() {
  if [ -n "${DEBUG:-}" ]; then
    set -x
  fi
  parse_args "$@"
  init

  prepare_branch
  for task_name in "${TASKS[@]}"; do
    echo
    echo "[$task_name]"
    "$SCRIPT_DIR/tasks/$task_name.sh"
  done
  show_summary
  revert_branch
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi
