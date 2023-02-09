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

task_init() {
  if [ -z "${COMMIT_MSG:-}" ]; then
    echo "[ERROR] Unset variable: COMMIT_MSG" >&2
    exit 1
  elif [ -e "$COMMIT_MSG" ]; then
    rm -f "$COMMIT_MSG"
  fi
  if [ -z "${WORKSPACE_DIR:-}" ]; then
    echo "[ERROR] Unset variable: WORKSPACE_DIR" >&2
    exit 1
  fi
}

task_end() {
  if [ -n "$BRANCH_NAME" ]; then
    commit_changes
  fi
}

commit_changes() {
  if ! git diff --quiet HEAD; then
    git add .
    git commit --file="$COMMIT_MSG" --quiet --signoff
  fi
}

main() {
  if [ -n "${DEBUG:-}" ]; then
    set -x
  fi
  task_init
  run_task
  task_end
  echo "Done"
}
