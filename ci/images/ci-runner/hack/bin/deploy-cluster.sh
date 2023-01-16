#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
set -x

kubectl -n "$NAMESPACE" apply -f "$WORKSPACE/hypershift_deployment.yaml"
echo "Wait until hypershift cluster is ready..."
wait_period=0
while
    [ \
        "$(
            kubectl -n "$NAMESPACE" get hypershiftdeployment "$CLUSTER_NAME" -o json \
                | jq -r '
                    .status.conditions[]? 
                    | select(.type == "HostedClusterProgress") 
                    | .reason
                '
        )" != "Completed" \
    ]; do
    if [ "$wait_period" -gt 1200 ]; then
        echo "[ERROR] Failed to create OCP cluster." >&2
        kubectl -n "$NAMESPACE" get hypershiftdeployment "$CLUSTER_NAME" -o yaml
        exit 1
    fi
    sleep 60
    wait_period=$((wait_period + 60))
    echo "Waited $wait_period seconds..."
done

echo "Hypershift is ready, the following is the cluster kubeconfig"
kubectl get secret -n clusters "$CLUSTER_NAME-admin-kubeconfig" -o json |
    jq -r '.data.kubeconfig' |
    base64 -d |
    tee "$WORKSPACE/kubeconfig"
