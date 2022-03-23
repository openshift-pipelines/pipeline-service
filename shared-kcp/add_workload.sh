#!/usr/bin/env bash

KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
SCRIPT_DIR="$(cd "$(dirname "$0")" >/dev/null ; pwd)"
KUBECONFIG_KCP="$SCRIPT_DIR/sharedkcp.kubeconfig"

KUBECONFIG=$KUBECONFIG kubectl apply -k $SCRIPT_DIR

KUBECONFIG=$KUBECONFIG kubectl config set-context --current --namespace=kcp-pcluster
KUBECONFIG=$KUBECONFIG ./create-workload-cluster.sh kcp > workload-cluster.yaml

KUBECONFIG=$KUBECONFIG_KCP kubectl apply -f workload-cluster.yaml