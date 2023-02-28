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

Build images from the project.

Optional arguments:
    -i, --image IMAGE_DIR
        Build the image which Dockerfile is located in IMAGE_DIR.
        Can be repeated to build multiple images.
        IMAGE_DIR must be in [$(echo "${DEFAULT_IMAGE_DIRS[@]}" | sed 's: :, :g')].
    -t, --tag TAG
        Tag to apply to the image.
        Default: latest
    -d, --debug
        Activate tracing/debug mode.
    -h, --help
        Display this message.

Example:
    ${0##*/}
" >&2
}

parse_args() {
  mapfile -t DEFAULT_IMAGE_DIRS < <(
    find "$PROJECT_DIR" -type f -name Dockerfile -exec dirname {} \; |
      sed "s:$PROJECT_DIR/::" |
      grep --invert-match --extended-regexp "/developer/exploration/|.devcontainer" |
      sort
  )
  IMAGE_DIRS=()
  while [[ $# -gt 0 ]]; do
    case $1 in
    -i | --image)
      shift
      if [ ! -d "$1" ]; then
        echo "[ERROR] Directory does not exists: $1" >&2
        exit 1
      else
        if [ ! -e "$1/Dockerfile" ]; then
          echo "[ERROR] Dockerfile not found in '$1'" >&2
          exit 1
        fi
      fi
      IMAGE_DIRS+=("$1")
      ;;
    -t | --tag)
      shift
      TAG="$1"
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
  TAG=${TAG:-latest}
  if [ -z "${IMAGE_DIRS[*]}" ]; then
    IMAGE_DIRS=("${DEFAULT_IMAGE_DIRS[@]}")
  fi

  detect_container_engine
}

detect_container_engine() {
    CONTAINER_ENGINE="${CONTAINER_ENGINE:-}"
    if [[ -n "${CONTAINER_ENGINE}" ]]; then
      return
    fi
    CONTAINER_ENGINE="podman"
    if ! command -v podman >/dev/null; then
        CONTAINER_ENGINE="docker"
        return
    fi
    if [[ "$OSTYPE" == "darwin"* && -z "$(podman ps)" ]]; then
        # Podman machine is not started
        CONTAINER_ENGINE="docker"
        return
    fi
    if [[ "$OSTYPE" == "darwin"* && -z "$(podman system connection ls --format=json)" ]]; then
        CONTAINER_ENGINE="docker"
        return
    fi
}

build_image() {
  echo "[$image_dir]"
  image_name=$(basename "$image_dir")
  case "$image_name" in
  quay-upload|vulnerability-scan)
    context="$image_dir"
    ;;
  *)
    context="$PROJECT_DIR"
    ;;
  esac
  $CONTAINER_ENGINE build --file "$image_dir/Dockerfile" --pull --tag "$image_name:$TAG" "$context"
  echo
}

main() {
  if [ -n "${DEBUG:-}" ]; then
    set -x
  fi
  parse_args "$@"
  init
  for image_dir in "${IMAGE_DIRS[@]}"; do
    build_image
  done
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi
