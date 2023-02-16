#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
set -x

echo "Start executing pipeline cases ..."
TEST_DIR=$(find "$PWD" -type f -name test.sh -exec dirname {} +)
"$TEST_DIR/test.sh" --kubeconfig /kubeconfig
