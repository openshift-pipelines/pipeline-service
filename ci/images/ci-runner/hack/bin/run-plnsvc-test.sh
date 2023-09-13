#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
set -x

echo "Run pipeline-service tests..."
if kubectl -n default exec pod/ci-runner -- \
    sh -c "/workspace/sidecar/bin/plnsvc_test.sh"; then

    # In case the user deleted the file early when they expected a failure
    if [ -e "$PWD/destroy-cluster.txt" ]; then
        # If the tests are successful, the cluster can be destroyed right away
        rm "$PWD/destroy-cluster.txt"
    fi
fi
