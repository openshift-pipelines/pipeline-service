#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -x
REPO_URL=$1
REPO_REVISION=$2

OPENSHIFT_DIR=$(find "$PWD" -type f -name dev_setup.sh -exec dirname {} +)
CONFIG="$OPENSHIFT_DIR/../config.yaml"
echo "Start executing pipeline-service setup ..."
yq -i e ".git_url=\"$REPO_URL\"" "$CONFIG"
yq -i e ".git_ref=\"$REPO_REVISION\"" "$CONFIG"

"$OPENSHIFT_DIR/dev_setup.sh" --debug
