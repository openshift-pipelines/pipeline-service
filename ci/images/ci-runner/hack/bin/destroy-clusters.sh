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

MAX_DURATION_MINS=120
EXCLUDE_CLUSTER=(local-cluster)

delete_cluster() {
    cluster_name="$1"
    deletionTimestamp=$(kubectl get hostedcluster -n clusters "$cluster_name" -o json \
        | jq -r '.metadata.deletionTimestamp?'
    )

    # If the the cluster has "deletionTimestamp" metadata, it means the cluster is triggered deletion
    if [ -z "$deletionTimestamp" ]; then
        return
    fi
    # If the cluster is older than $MAX_DURATION_MINS mins, it will be deleted
    creationTime=$(kubectl -n clusters get hostedcluster "$cluster_name" -o json | jq -r '.metadata.creationTimestamp')
    durations_mins=$((($(date +%s) - $(date +%s -d "$creationTime")) / 60))
    if [ "$durations_mins" -gt "$MAX_DURATION_MINS" ]; then
        echo "Start delete cluster $cluster_name"
        open_bitwarden_session
        get_aws_credentials
        hypershift destroy cluster aws --aws-creds "$AWS_CREDENTIALS"  --name "$cluster_name"
    fi
}

mapfile -t clusters < <(kubectl get hostedcluster -n clusters -o=custom-columns=NAME:.metadata.name --no-headers)
for cluster in "${clusters[@]}"; do
    if [[ "${EXCLUDE_CLUSTER[*]}" =~ $cluster ]]; then
        continue
    fi
    delete_cluster "$cluster"
done
