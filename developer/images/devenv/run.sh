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

usage() {
    echo "
Usage:
    ${0##*/} [options]

Run a container with the development environment.

Optional arguments:
    --dev
        Build and run a local image
    -f, --force
        Force the creation of a new container
    -d, --debug
        Activate tracing/debug mode.
    -h, --help
        Display this message.

Example:
    ${0##*/}
" >&2
}

init() {
    SCRIPT_DIR=$(
        cd "$(dirname "$0")" >/dev/null
        pwd
    )
    PROJECT_DIR=$(
        cd "$SCRIPT_DIR" >/dev/null
        git rev-parse --show-toplevel
    )
    DEV_MODE="0"
    IMAGE_NAME="quay.io/redhat-pipeline-service/devenv:main"
    LOCAL_IMAGE_NAME="$IMAGE_NAME"
    CONTAINER_NAME=$(pwd | sed -e 's:/:__:g' -e 's:[^a-zA-Z0-9_-]:-:g' | cut -c3-)

    detect_container_engine
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
        --dev)
            DEV_MODE="1"
            ;;
        -f | --force)
            $CONTAINER_ENGINE rm -f "$CONTAINER_NAME" &>/dev/null || true
            ;;
        -d | --debug)
            set -x
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

detect_container_engine() {
    CONTAINER_ENGINE="${CONTAINER_ENGINE:-}"
    ALLOW_ROOTLESS="${ALLOW_ROOTLESS:-false}"
    if [[ -n "${CONTAINER_ENGINE}" ]]; then
        return
    fi

    # Check if docker should be used
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

    # Default container engine is podman
    CONTAINER_ENGINE="sudo podman"
    if [[ "${ALLOW_ROOTLESS}" == "true" ]]; then
        CONTAINER_ENGINE="podman"
    fi
}

get_image_name() {
    DEPENDENCIES_SHA=$(
        cat "$SCRIPT_DIR/Dockerfile" "$SCRIPT_DIR/install.sh" "$PROJECT_DIR/config/dependencies.yaml" |
            sha256sum | cut -c1-8
    )
    IMAGE_NAME="pipeline-service/devenv:$DEPENDENCIES_SHA"
    LOCAL_IMAGE_NAME="localhost/$IMAGE_NAME"
}

build_image() {
    if [ "$("${CONTAINER_ENGINE[@]}" images --filter "reference=$LOCAL_IMAGE_NAME" --noheading | wc -l)" = "0" ]; then
        echo "[Building container]"
        $CONTAINER_ENGINE build -f "$SCRIPT_DIR/Dockerfile" --label "name=$IMAGE_NAME" -t "$IMAGE_NAME" "$PROJECT_DIR"
    fi
}

start_container() {
    if ! $CONTAINER_ENGINE ps --filter "name=$CONTAINER_NAME" | grep -q "$IMAGE_NAME"; then
        if ! $CONTAINER_ENGINE ps -a --filter "name=$CONTAINER_NAME" | grep -q "$IMAGE_NAME"; then
            echo "[Starting container]"
            $CONTAINER_ENGINE rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
            if [ "$DEV_MODE" = "0" ]; then
                CONTAINER_ENGINE_OPTS=("--pull" "always")
            fi
            $CONTAINER_ENGINE run \
                --detach \
                --entrypoint '["bash", "-c", "sleep infinity"]' \
                --name "$CONTAINER_NAME" \
                --privileged \
                --volume "$PROJECT_DIR:/workspace"
                "${CONTAINER_ENGINE_OPTS[@]}" \
                "$LOCAL_IMAGE_NAME" >/dev/null 2>&1
        else
            echo "[Restarting container]"
            $CONTAINER_ENGINE start "$CONTAINER_NAME" >/dev/null 2>&1
        fi
    fi
}

open_shell() {
    echo "[Opening shell in container]"
    $CONTAINER_ENGINE exec -it "$CONTAINER_NAME" /bin/bash
}

stop_container() {
    # Stop container when the last shell exits
    if ! $CONTAINER_ENGINE exec "$CONTAINER_NAME" /bin/sh -c "ps -ef | grep ' /bin/bash$'"; then
        echo "[Stopping container]"
        $CONTAINER_ENGINE stop "$CONTAINER_NAME" >/dev/null
    fi
}

main() {
    init
    parse_args "$@"
    if [ "$DEV_MODE" != "0" ]; then
        get_image_name
        build_image
    fi
    start_container
    open_shell
    stop_container
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
    main "$@"
fi
