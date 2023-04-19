#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
set -x

SCRIPT_DIR="$(
  cd "$(dirname "$0")" >/dev/null
  pwd
)"

# Give developers 15mins to connect to a pod and remove the file
# if they want to investigate the failure
if [ -e "$PWD/destroy-cluster.txt" ]; then
    sleep 900
    if [ -e "$PWD/destroy-cluster.txt" ]; then
      echo "Failure is not being investigated, cluster will be destroyed."
    else
      echo "KUBECONFIG:"
      cat "$KUBECONFIG"
      echo
      echo "Connect to the ci-runner: kubectl exec -n default --stdin --tty ci-runner -- bash"
      echo
      echo "Failure under investigation, cluster will not be destroyed."
      exit 1
    fi
fi

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
