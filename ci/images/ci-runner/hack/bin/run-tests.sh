#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
set -x

echo "Execute test.sh script to verify pipeline-service ..."
kubectl -n default exec pod/ci-runner -- \
    sh -c "/source/ci/images/ci-runner/hack/sidecar/bin/plnsvc_test.sh"
