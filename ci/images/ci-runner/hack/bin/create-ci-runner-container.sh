#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
set -x

kubectl -n openshift-config get secret/pull-secret -o yaml >/tmp/pull-secret.yaml
yq -i '.metadata.namespace="default" |
    del(.type) | 
    del(.metadata.uid) | 
    del(.metadata.resourceVersion) | 
    .data.["auth.json"]=.data.[".dockerconfigjson"] | 
    del(.data.[".dockerconfigjson"])' \
    /tmp/pull-secret.yaml
kubectl -n default apply -f /tmp/pull-secret.yaml

MANIFEST_DIR=$(
    cd "$(dirname "$0")/../manifests";
    pwd;
)
kubectl -n default apply -k "$MANIFEST_DIR/sidecar"

kubectl -n default wait pod/ci-runner --for=condition=Ready --timeout=90s
kubectl -n default describe pod/ci-runner
