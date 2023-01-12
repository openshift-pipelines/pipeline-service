#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -x

echo "Start executing pipeline cases ..."
TEST_DIR=$(find "$PWD" -type f -name test.sh -exec dirname {} +)
KUBECONFIG=/kubeconfig CASES=pipelines "$TEST_DIR/test.sh"
