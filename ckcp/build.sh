#!/usr/bin/env bash

set -exuo pipefail

docker build -t "$KO_DOCKER_REPO/ckcp" docker/ckcp/
