#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
set -x

echo "Copy source code of pipeline service to the ci-runner container"
for _ in {1..10}; do
    if kubectl cp "./" "default/ci-runner:/workspace/source"; then
        break
    fi
    echo "Failed to copy source code of pipeline service to the ci-runner container, retrying ..."
    sleep 5
done

echo "Copy sidecar sources to the ci-runner container"
for _ in {1..10}; do
    if kubectl cp "./ci/images/ci-runner/hack/sidecar" "default/ci-runner:/workspace/sidecar"; then
        break
    fi
    echo "Failed to copy sidecar sources to the ci-runner container, retrying ..."
    sleep 5
done

echo "Copy new cluster's kubeconfig to the ci-runner container"
for _ in {1..10}; do
    if kubectl cp "$KUBECONFIG" "default/ci-runner:/kubeconfig"; then
        break
    fi
    echo "Failed to copy cluster's kubeconfig to the ci-runner container, retrying ..."
    sleep 5
done
