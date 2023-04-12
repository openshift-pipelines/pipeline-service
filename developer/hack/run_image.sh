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
    ${0##*/} [options] IMAGE_DIR

Run an image built from the project. The image will be always be rebuilt from the latest
content.

Mandatory arguments:
    IMAGE_DIR
        Path to the directory in which the Dockerfile for the image is located.
        Must be one of [$(
          find "$PROJECT_DIR" -type f -name Dockerfile -exec dirname {} \; |
          grep --invert-match --extended-regexp "/developer/exploration/" |
          sort |
          tr '\n' ' ' |
          sed -e 's: :, :g' -e 's:..$::' -e "s:$PROJECT_DIR/::g"
)].

Optional arguments:
    -- CONTAINER_RUN_ARGS
        Arguments to pass to the container.
        Must be last.
    -q, --quiet
        Only output information from the container run.
    -t, --tty
        Open a terminal.
    -w, --workspace_dir WORKSPACE_DIR.
        Workspace directory.
        Default: $PROJECT_DIR
    -d, --debug
        Activate tracing/debug mode.
    -h, --help
        Display this message.

Example:
    ${0##*/} --quiet ci/images/shellcheck -- --workspace_dir $PROJECT_DIR
" >&2
}

parse_args() {
  CONTAINER_OPTIONS=( "--rm" )
  WORKSPACE_DIR="$PROJECT_DIR"
  STDOUT="/dev/stdout"
  while [[ $# -gt 0 ]]; do
    case $1 in
    -q | --quiet)
      STDOUT="/dev/null"
      ;;
    -t | --tty)
      CONTAINER_OPTIONS+=( "--entrypoint" "/bin/sh" "--interactive" "--tty" )
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
    --)
      shift
      CONTAINER_RUN_CMD=( "$@" )
      break
      ;;
    *)
      if [ ! -d "$1" ]; then
        usage
        echo "[ERROR] Directory does not exists: $1" >&2
        exit 1
      else
        if [ ! -e "$1/Dockerfile" ]; then
          usage
          echo "[ERROR] Dockerfile not found in '$1'" >&2
          exit 1
        fi
      fi
      IMAGE_DIR="$1"
      ;;
    esac
    shift
  done
}

init() {
  if [ -z "${IMAGE_DIR}" ]; then
    echo "[ERROR] Missing argument: IMAGE_DIR" >&2
    exit 1
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
  echo [Build image]
  "$SCRIPT_DIR/build_image.sh" -i "$IMAGE_DIR"
}

run_image() {
  image_name=$(basename "$IMAGE_DIR")
  if [ "$CONTAINER_ENGINE" = "podman" ]; then
    image_name="localhost/$image_name"
  fi
  if [ -z "$WORKSPACE_DIR" ]; then
    case $image_name in
      .devcontainer|devenv|shellcheck|yamllint)
        WORKSPACE_DIR="$PROJECT_DIR"
        ;;
    esac
  fi

  if [ -n "$WORKSPACE_DIR" ]; then
    CONTAINER_OPTIONS+=( "--volume" "$WORKSPACE_DIR:/workspace:Z" )

    # These settings are required to run dev_setup.sh successfully
    CONTAINER_OPTIONS+=( "--privileged" "--volume" "/var/run/podman:/var/run/podman" )  # Enable podman in podman
    CONTAINER_OPTIONS+=( "--volume" "$HOME/.kube:/root/.kube:Z" "--volume" "$HOME/.ssh:/root/.ssh:Z" )  # Access user's config
  fi

  echo "[Run $image_name]" >"$STDOUT"
  $CONTAINER_ENGINE run "${CONTAINER_OPTIONS[@]}" "$image_name" "${CONTAINER_RUN_CMD[@]}"
}

main() {
  if [ -n "${DEBUG:-}" ]; then
    set -x
  fi
  parse_args "$@"
  init
  build_image >"$STDOUT"
  run_image
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi
