#!/usr/bin/env bash
set -o nounset
set -o pipefail
set -o errexit

if ! which jq &> /dev/null; then
    echo "Install jq"
    exit 1
fi

if [ $# -eq 0 ]; then
    echo "Pass the service account name"
    exit 1
fi

token_secret=$(kubectl get sa $1 -o json | jq -r '.secrets[].name | select(. | test(".*token.*"))')
current_context=$(kubectl config current-context)
current_cluster=$(kubectl config view -o jsonpath="{.contexts[?(@.name==\"$current_context\")].context.cluster}")

kubectl config set-credentials kcp-sa --token=$(kubectl get secret $token_secret -o jsonpath={.data.token} | base64 -d) &> /dev/null
kubectl config set-context kcp-internal --user=kcp-sa --cluster=$current_cluster &> /dev/null
kubectl config use-context kcp-internal &> /dev/null

cat <<EOF
apiVersion: workload.kcp.dev/v1alpha1
kind: WorkloadCluster
metadata:
  name: kcp-pcluster
spec:
  kubeconfig: |
$(kubectl config view --flatten --minify|sed 's,^,    ,')
EOF

kubectl config use-context $current_context &> /dev/null
