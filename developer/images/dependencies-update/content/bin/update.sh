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
    -c, --commit_to BRANCH_NAME
        Commit changes to BRANCH_NAME
        Default: robot/\$CURRENT_BRANCH_NAME/update_dependencies.
    -t, --task TASKNAME
        Only run the selected task. Can be repeated to run multiple tasks.
        TASKNAME must be in [$(echo "${DEFAULT_TASKS[@]}" | sed 's: :, :')].
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
  mapfile -t DEFAULT_TASKS < <(find "$SCRIPT_DIR/tasks" -type f -name \*.sh -exec basename {} \; | sed 's:...$::')
  TASKS=()
  WORKSPACE_DIR="$PROJECT_DIR"
  while [[ $# -gt 0 ]]; do
    case $1 in
    -c | --commit_to)
      shift
      BRANCH_NAME="$1"
      ;;
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
  export BRANCH_NAME
  export COMMIT_MSG
  export WORKSPACE_DIR
  cd "$WORKSPACE_DIR"
}

prepare_branch(){
  CURRENT_BRANCH_NAME=$(git branch --show-current)
  BRANCH_NAME=${BRANCH_NAME:-robot/$CURRENT_BRANCH_NAME/update_dependencies}

  # Revert any change to the current branch
  if ! git diff --quiet; then
    git stash --include-untracked
    GIT_STASH="true"
  fi
  GIT_STASH=${GIT_STASH:-}

  # Create a new branch from the current branch
  git branch --copy --force "$BRANCH_NAME"
  git checkout "$BRANCH_NAME"
}

push_changes(){
  if ! git diff --quiet "$CURRENT_BRANCH_NAME"; then
    echo "[Summary]"
    git log --format="%B" "$CURRENT_BRANCH_NAME..HEAD"
    git push --force --quiet --set-upstream origin "$BRANCH_NAME"
  fi
}

revert_to_current_branch(){
  git checkout "$CURRENT_BRANCH_NAME"
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
    echo "[$task_name]"
    "$SCRIPT_DIR/tasks/$task_name.sh"
    echo
  done
  push_changes
  revert_to_current_branch
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi
