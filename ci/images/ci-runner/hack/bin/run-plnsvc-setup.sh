#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
set -x

echo "Execute dev_setup.sh script to set up pipeline-service ..."
kubectl -n default exec pod/ci-runner -- \
    sh -c "/source/ci/images/ci-runner/hack/sidecar/bin/plnsvc_setup.sh"
