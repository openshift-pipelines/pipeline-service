#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
set -x

if [[ "$CLUSTER_STATUS" != "None" ]]; then
    echo "Started to destroy cluster [$CLUSTER_NAME]..."
    kubectl -n "$NAMESPACE" delete HypershiftDeployment "$CLUSTER_NAME"
    echo "Successfully destroyed cluster"
else
    echo "No OCP cluster need to be destroyed."
fi
