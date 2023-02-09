#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
set -x

echo "Execute test.sh script to verify pipeline-service ..."
kubectl -n default exec pod/ci-runner -- \
    sh -c "/source/ci/images/ci-runner/hack/sidecar/bin/plnsvc_test.sh" || FAIL="1"
if [ -n "${FAIL:-}" ]; then
    cat "$KUBECONFIG"
    echo
    echo "Debug with: kubectl exec -n default pod/ci-runner -it -- sh"
    sleep 1200
    exit 1
fi
