#!/usr/bin/env bash

set -exuo pipefail

parent_path=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )
pushd "$parent_path"

source ../local/.utils

detect_container_engine

IMAGE="$KO_DOCKER_REPO/ckcp:986710c754ed0dac9ae1525661de931e5dd7c0cc"
${CONTAINER_ENGINE} build -t "$IMAGE" docker/ckcp/
${CONTAINER_ENGINE} push "$IMAGE"

popd
