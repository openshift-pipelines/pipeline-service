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

fetch_bitwarden_secrets() {
    printf "Fetch secrets from bitwarden server\n" | indent 2
    open_bitwarden_session
    get_base_domain
    get_pull_secret
    get_aws_credentials
}

print_debug_info() {
    printf "Print debug info......\n" | indent 2

    printf "HostedCluster CR Status: " | indent 4
    kubectl -n clusters get hostedcluster "$CLUSTER_NAME" -o yaml

    printf "Control Plane pods of HostedCluster: " | indent 4
    kubectl -n "clusters-${CLUSTER_NAME}" get pods

    # Export kubeconfig of hosted cluster
    hypershift create kubeconfig --name "$CLUSTER_NAME" > "${CLUSTER_NAME}.kubeconfig"

    printf "Cluster Operators on Hosted Cluster: " | indent 4
    kubectl --kubeconfig="${CLUSTER_NAME}.kubeconfig" get co -o yaml
}

deploy_cluster() {
    setx_off
    hypershift create cluster aws \
        --pull-secret "$PULL_SECRET" \
        --aws-creds "$AWS_CREDENTIALS" \
        --name "$CLUSTER_NAME" \
        --node-pool-replicas=2 \
        --base-domain "$BASE_DOMAIN" \
        --region="$REGION" \
        --release-image="$IMAGE" \
        --root-volume-type=gp3 \
        --root-volume-size=120 \
        --instance-type=m5.2xlarge \
        --arch=amd64
    setx_on

    echo "Wait until hypershift hosted cluster is ready..."
    wait_period=0
    while
        [ \
            "$(
                kubectl -n clusters get hostedcluster "$CLUSTER_NAME" -o json \
                    | jq -r '.status.version.history[0].state'
            )" != "Completed" \
        ]; do
        if [ "$wait_period" -gt 1800 ]; then
            echo "[ERROR] Failed to create OCP cluster." >&2
            print_debug_info
            exit 1
        fi
        sleep 60
        wait_period=$((wait_period + 60))
        echo "Waited $wait_period seconds..."
    done

    echo "Hypershift is ready, The following is Cluster credentials"
    local pass
    pass="$(kubectl get secret -n clusters "${CLUSTER_NAME}"-kubeadmin-password -o json | jq -r .data.password | base64 -d)"
    echo "kubeadmin:${pass}"
    echo "The following is the cluster kubeconfig"

    hypershift create kubeconfig --name "$CLUSTER_NAME" | tee "$WORKSPACE/kubeconfig"
}

fetch_bitwarden_secrets
deploy_cluster