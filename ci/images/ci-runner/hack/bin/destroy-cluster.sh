#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
set -x

SCRIPT_DIR="$(
  cd "$(dirname "$0")" >/dev/null
  pwd
)"

# shellcheck source=ci/images/ci-runner/hack/bin/utils.sh
source "$SCRIPT_DIR/utils.sh"

if [[ -n "$CLUSTER_NAME"  ]]; then
    echo "Started to destroy cluster [$CLUSTER_NAME]..."
    open_bitwarden_session
    get_aws_credentials
    hypershift destroy cluster aws --aws-creds "$AWS_CREDENTIALS"  --name "$CLUSTER_NAME"
    echo "Successfully destroyed cluster"
else
    echo "No OCP cluster need to be destroyed."
fi
