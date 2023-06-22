#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
set -x

echo "Start executing pipeline cases ..."
TEST_DIR=$(find "$PWD" -type f -name test.sh -exec dirname {} +)
"$TEST_DIR/test.sh" --kubeconfig "$KUBECONFIG"


# In case the user deleted the file early when they expected a failure
if [ -e "$PWD/destroy-cluster.txt" ]; then
    # If the tests are successful, the cluster can be destroyed right away
    rm "$PWD/destroy-cluster.txt"
fi
