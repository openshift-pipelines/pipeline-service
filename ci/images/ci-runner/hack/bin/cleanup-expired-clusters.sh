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

EXCLUDE_CLUSTER=(local-cluster newci4plnsvc)

fetch_bitwarden_secrets() {
    printf "Fetch secrets from bitwarden server\n" | indent 2
    open_bitwarden_session
    get_aws_credentials
    get_rosa_token
}

is_cluster_expired() {
    cluster_name=$1

    if ! rosa describe cluster --region "$REGION" --cluster="$cluster_name" -o json | \
        jq -e 'select((.creation_timestamp | fromdateiso8601) < (now - 7200))' >/dev/null; then
        echo "false"
    fi
    echo "true"
}

destroy_expired_clusters() {
    mapfile -t clusters < <(rosa list clusters --region "$REGION" | grep "ready" | awk '{print $2}')

    for cluster in "${clusters[@]}"; do
        if [[ "${EXCLUDE_CLUSTER[*]}" =~ $cluster ]]; then
            continue
        fi

        is_expired=$(is_cluster_expired "$cluster")
        
        if [[ "$is_expired" == "true" ]]; then
            export CLUSTER_NAME="$cluster" 
            "$SCRIPT_DIR"/destroy-cluster.sh 
        fi
    done
}

fetch_bitwarden_secrets
setx_off
rosa login --token="$ROSA_TOKEN"
setx_on
destroy_expired_clusters