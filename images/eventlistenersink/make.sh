#!/usr/bin/env bash

# Copyright 2022 The pipelines-service Authors.
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

set -x
SCRIPT_DIR="$(
  cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null
  pwd
)"

usage() {
  echo "
Usage:
  ${0##*/} [options]

Build the modified eventlistenersink image for pipelines service

Optional arguments:
    -w, --workdir
        Path to the working directory.
        Default: a random directory in \"${TMPDIR:-/tmp}\"
    -d, --debug
        Activate tracing/debug mode.
    -h, --help
        Display this message.

Example:
  ${0##*/} --all
" >&2
}

parse_args() {
  local args
  args="$(getopt -o dhw: -l "debug,help,workdir" -n "$0" -- "$@")"
  eval set -- "$args"
  while true; do
    case $1 in
    -w | --workdir)
      shift
      WORK_DIR="$(cd "$1" >/dev/null; pwd)"
      ;;
    -d | --debug)
      set -x
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --)
      # End of arguments
      break
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
  WORK_DIR=${WORK_DIR:-}
  if [ -z "$WORK_DIR" ]; then
    WORK_DIR="$(mktemp -d -t eventlistenersink.XXXXXXXXX)"
  fi
  mkdir -p "$WORK_DIR"
  UPSTREAM_DIR="$WORK_DIR/upstream"
}

checkout_upstream_repo() {
  if [ ! -e "$UPSTREAM_DIR" ]; then
    git clone "https://github.com/tektoncd/triggers.git" "$UPSTREAM_DIR"
  fi
  pushd "$UPSTREAM_DIR"
  git checkout -f "v0.18.0"
}

apply_patches() {
  for patch in "$SCRIPT_DIR/patches"/*; do
    git apply "$patch"
  done
}

publish() {
  pushd "$UPSTREAM_DIR/cmd/eventlistenersink"
  ko publish .
}

main() {
  parse_args "$@"
  init
  checkout_upstream_repo
  apply_patches
  publish
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi