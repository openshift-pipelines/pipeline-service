#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
set -x

export KUBECONFIG="/kubeconfig"

OPENSHIFT_DIR=$(find "$PWD" -type f -name dev_setup.sh -exec dirname {} +)

echo "Start executing pipeline-service setup ..."

"$OPENSHIFT_DIR/dev_setup.sh" --debug --use-current-branch --force --work-dir "$OPENSHIFT_DIR/work"
