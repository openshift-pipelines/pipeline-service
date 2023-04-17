#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
set -x

# Create a file that will prevent the cluster deletion in case tests are failing
touch "$PWD/destroy-cluster.txt"

echo "Execute dev_setup.sh script to set up pipeline-service ..."
kubectl -n default exec pod/ci-runner -- \
    sh -c "/source/ci/images/ci-runner/hack/sidecar/bin/plnsvc_setup.sh $REPO_URL $REPO_REVISION"
