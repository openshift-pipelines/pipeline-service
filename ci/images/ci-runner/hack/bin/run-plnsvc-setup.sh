#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
set -x

# Create a file that will prevent the cluster deletion in case tests are failing
touch "$PWD/destroy-cluster.txt"

echo "Execute dev_setup.sh script to set up pipeline-service ..."
# if the following comand fail, it retries 3 times with 5 seconds sleep
for _ in {1..3}; do
    if kubectl -n default exec pod/ci-runner -- \
        sh -c "/workspace/sidecar/bin/plnsvc_setup.sh $REPO_URL $REPO_REVISION"; then
        break
    fi
    echo "Failed to execute dev_setup.sh script, retrying ..."
    sleep 5
done
    
