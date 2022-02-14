#!/usr/bin/env bash

set -exuo pipefail

IMAGE="$KO_DOCKER_REPO/ckcp:986710c754ed0dac9ae1525661de931e5dd7c0cc"
docker build -t "$IMAGE" docker/ckcp/
docker push "$IMAGE"
