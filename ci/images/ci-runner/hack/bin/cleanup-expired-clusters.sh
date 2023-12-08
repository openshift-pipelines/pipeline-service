#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(
  cd "$(dirname "$0")" >/dev/null
  pwd
)"

# shellcheck source=ci/images/ci-runner/hack/bin/utils.sh
source "$SCRIPT_DIR/utils.sh"

EXCLUDE_CLUSTER=(local-cluster sprayproxy-qe1)

is_cluster_expired() {
    cluster_name=$1

    if ! rosa describe cluster --region "$REGION" --cluster="$cluster_name" -o json | \
        jq -e 'select((.creation_timestamp | fromdateiso8601) < (now - 7200))' >/dev/null; then
        echo "false"
    fi
    echo "true"
}

destroy_expired_clusters() {
    expired_clusters=()
    mapfile -t clusters < <(rosa list clusters --region "$REGION" | grep "ready" | awk '{print $2}')

    echo "[$(date +"%Y/%m/%d %H:%M:%S")] Cluster count: ${#clusters[@]}"
    for cluster in "${clusters[@]}"; do
        if [[ "$cluster" =~ ^debug- || "${EXCLUDE_CLUSTER[*]}" =~ $cluster ]]; then
            continue
        fi

        is_expired=$(is_cluster_expired "$cluster")
        
        if [[ "$is_expired" == "true" ]]; then
            expired_clusters+=( "$cluster" )
        fi
    done

    echo "[$(date +"%Y/%m/%d %H:%M:%S")] Expired cluster count: ${#expired_clusters[@]}"
    count=0
    for cluster in "${expired_clusters[@]}"; do
        count=$(( count + 1 ))
        echo "Destroying $cluster [$count/${#expired_clusters[@]}]"
        export CLUSTER_NAME="$cluster"
        "$SCRIPT_DIR"/destroy-cluster.sh
    done
}

setx_off
rosa login --token="$ROSA_TOKEN"
setx_on
destroy_expired_clusters
