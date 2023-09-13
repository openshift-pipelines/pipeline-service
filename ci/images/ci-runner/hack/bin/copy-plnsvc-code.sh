#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
set -x

echo "Copy source code of pipeline service to the ci-runner container"
kubectl cp "./" "default/ci-runner:/workspace/source"

echo "Copy sidecar sources to the ci-runner container"
kubectl cp "./ci/images/ci-runner/hack/sidecar" "default/ci-runner:/workspace/sidecar"

echo "Copy new cluster's kubeconfig to the ci-runner container"
kubectl cp "$KUBECONFIG" "default/ci-runner:/kubeconfig"
