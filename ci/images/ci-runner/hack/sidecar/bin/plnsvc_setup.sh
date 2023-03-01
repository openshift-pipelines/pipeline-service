#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
set -x

export KUBECONFIG="/kubeconfig"
REPO_URL=$1
REPO_REVISION=$2

DEV_DIR=$(find "$PWD" -type f -name dev_setup.sh -exec dirname {} +)
CONFIG="$DEV_DIR/config.yaml"

echo "Start executing pipeline-service setup ..."
yq -i e ".git_url=\"$REPO_URL\"" "$CONFIG"
yq -i e ".git_ref=\"$REPO_REVISION\"" "$CONFIG"

"$DEV_DIR/dev_setup.sh" --debug --use-current-branch --force --work-dir "$DEV_DIR/work"
