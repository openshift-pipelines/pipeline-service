#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
set -x

MAX_DURATION_MINS=60
EXCLUDE_CLUSTER=(local-cluster)

delete_cluster() {
    cluster_name="$1"
    status=$(kubectl -n ci-clusters get hd "$cluster_name" -o json \
        | jq -r '
            .status.conditions[]? 
            | select(.type == "ManifestWorkConfigured") 
            |.reason
        '
    )
    # If the the cluster is Removing state, it won't delete this cluster
    if [ "$status" = "Removing" ]; then
        return
    fi
    # If the cluster is older than $MAX_DURATION_MINS mins, it will be deleted
    creationTime=$(kubectl -n ci-clusters get hd "$cluster_name" -o json | jq -r '.metadata.creationTimestamp')
    durations_mins=$((($(date +%s) - $(date +%s -d "$creationTime")) / 60))
    if [ "$durations_mins" -gt "$MAX_DURATION_MINS" ]; then
        echo "Start delete cluster $cluster_name"
        kubectl -n ci-clusters delete hd "$cluster_name"
    fi
}

mapfile -t clusters < <(kubectl get managedcluster -o=custom-columns=NAME:.metadata.name --no-headers)
for cluster in "${clusters[@]}"; do
    if [[ "${EXCLUDE_CLUSTER[*]}" =~ $cluster ]]; then
        continue
    fi
    delete_cluster "$cluster"
done
