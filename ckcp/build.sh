#!/usr/bin/env bash

set -exuo pipefail

IMAGE="$KO_DOCKER_REPO/ckcp:dfc490d656822da51234c9c18678c3a0c7952c0d"
docker build -t "$IMAGE" docker/ckcp/
docker push "$IMAGE"
