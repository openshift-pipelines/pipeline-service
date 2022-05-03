#!/usr/bin/env bash

# Copyright 2022 The pipelines-service Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(
  cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null
  pwd
)"

source "$SCRIPT_DIR/common.sh"

usage() {
  echo "
Usage:
    ${0##*/} [options]

Setup the pipeline service on a cluster running on KCP." >&2
  usage_args
}

configure_pipeline_cluster() {
  echo "[Pipeline cluster]"

  echo "  - Setup the cluster:"
  plnsvc_config kubectl apply -f "$SCRIPT_DIR/manifests/plnsvc/namespace.yaml"

  echo "  - Service account for connecting the plnsvc cluster to ArgoCD: "
  plnsvc_config kubectl apply -f "$SCRIPT_DIR/manifests/plnsvc/argocd-manager.yaml"

  echo "  - Service account for connecting KCP to the plnsvc cluster:"
  plnsvc_config kubectl apply -f "$SCRIPT_DIR/manifests/plnsvc/kcp-manager.yaml"

  echo
}

configure_kcp_cluster() {
  echo "[KCP cluster]"

  echo "  - Service account for connecting the pipelines controller to KCP: "
  kcp_config kubectl apply -f "$SCRIPT_DIR/manifests/kcp/plnsvc-manager.yaml"
  get_context kcp_config "$KCP_ENV-plnsvc" plnsvc plnsvc-manager "$KUBECONFIG_KCP_PLNSVC"

  # Setup the resources required for ArgoCD to manage the KCP cluster
  # Check if this can be deprecated when ArgoCD runs on KCP instead of the Pipeline cluster
  echo "  - Service account for connecting KCP to ArgoCD: "
  kcp_config kubectl apply -f "$SCRIPT_DIR/manifests/kcp/argocd-manager.yaml"
  get_context kcp_config "$KCP_ENV-argocd" kube-system argocd-manager "$KUBECONFIG_KCP_ARGOCD"

  echo -n "  - Create plnsvc workloadcluster: "
  local manifests_dir="$WORK_DIR/manifests"
  mkdir -p "$manifests_dir/plnsvc"
  if ! kcp_config kubectl get workloadcluster plnsvc >/dev/null 2>&1; then
    kcp_config kubectl kcp workload sync plnsvc --kcp-namespace plnsvc \
      --resources pods,services \
      --syncer-image ghcr.io/kcp-dev/kcp/syncer-c2e3073d5026a8f7f2c47a50c16bdbec:41ca72b > "$manifests_dir/plnsvc/kcp-syncer.yaml"
  fi
  echo "OK"

  echo
}

register_clusters() {
  echo "[Clusters registration]"

  echo "  - Register the plnsvc cluster to KCP: "
  if [ -f "$WORK_DIR/manifests/plnsvc/kcp-syncer.yaml" ]; then
    plnsvc_config kubectl apply -f "$WORK_DIR/manifests/plnsvc/kcp-syncer.yaml"
  fi

  echo -n "  - Register pipelines-cluster to ArgoCD as '$CLUSTER_NAME': "
  KUBECONFIG="$KUBECONFIG_PLNSVC" argocd_local cluster add \
    "$(yq ".current-context" <"$KUBECONFIG_PLNSVC")" \
    --service-account argocd-manager --name="$CLUSTER_NAME" --upsert --yes >/dev/null
  echo "OK"

  # Register the KCP cluster to ArgoCD
  # Check if this can be deprecated when ArgoCD runs on KCP instead of the Pipeline cluster
  local argcocd_cluster_name="kcp"
  echo -n "  - Register KCP cluster to ArgoCD as '$argcocd_cluster_name': "
  KUBECONFIG="$KUBECONFIG_KCP_ARGOCD" argocd_local cluster add "$KCP_ENV-argocd" \
    --name="$argcocd_cluster_name" --service-account argocd-manager --upsert --yes >/dev/null
  echo "OK"

  echo
}

install_operators() {
  echo "[Install operators]"
  local gitops_path
  gitops_path="$(
    cd "$SCRIPT_DIR/../gitops"
    pwd
  )"

  echo "  - on KCP: "
  # Setup the cluster
  kcp_config kubectl apply -f "$gitops_path/triggers/triggers-crds/base/namespace.yaml"
  kcp_config kubectl apply -f "https://raw.githubusercontent.com/tektoncd/pipeline/v0.32.0/config/100-namespace.yaml"

  # Create the secrets so the event listener and interceptors can talk to KCP
  kcp_config kubectl create secret generic kcp-kubeconfig --from-file "$KUBECONFIG_KCP_PLNSVC" \
    --dry-run=client -o yaml | \
    sed "s%^  $(basename "$KUBECONFIG_KCP_PLNSVC"): %  admin.kubeconfig: %" | \
    kcp_config kubectl apply -f -
  kcp_config kubectl create secret generic kcp-kubeconfig -n tekton-pipelines \
    --from-file "$KUBECONFIG_KCP_PLNSVC" --dry-run=client -o yaml |
    sed "s%^  $(basename "$KUBECONFIG_KCP_PLNSVC"): %  admin.kubeconfig: %" | \
    kcp_config kubectl apply -f -

  # Deploy the operators
  for app in pipelines-crds triggers-crds triggers-interceptors; do
    plnsvc_config kubectl apply -f "$gitops_path/$app.yaml"
  done

  echo "  - on plnsvc: "

  # Create kcp-kubeconfig secret for the controllers
  plnsvc_config kubectl create secret generic kcp-kubeconfig -n pipelines \
    --from-file "$KUBECONFIG_KCP_PLNSVC" --dry-run=client -o yaml |
    sed "s%^  $(basename "$KUBECONFIG_KCP_PLNSVC"): %  admin.kubeconfig: %" | \
    plnsvc_config kubectl apply -f -
  plnsvc_config kubectl create secret generic kcp-kubeconfig -n triggers \
    --from-file "$KUBECONFIG_KCP_PLNSVC" --dry-run=client -o yaml |
    sed "s%^  $(basename "$KUBECONFIG_KCP_PLNSVC"): %  admin.kubeconfig: %" | \
    plnsvc_config kubectl apply -f -

  # Deploy the operators
  for app in pipelines-controller triggers-controller; do
    plnsvc_config kubectl apply -f "$gitops_path/$app.yaml"
  done

  echo -n "  - ArgoCD applications are healthy: "
  local argocd_apps
  argocd_apps="$(argocd_local app list -o name)"
  argocd_local app wait "${argocd_apps[@]}" > /dev/null
  echo "OK"

  echo
}

get_context() {
  # Helper function to generate a kubeconfig file for a service account
  local cluster_config="$1"
  local sa_context="$2"
  local namespace="$3"
  local sa="$4"
  local target="$5"
  local current_context
  current_context="$($cluster_config kubectl config current-context)"

  if ! which jq &>/dev/null; then
    echo "[ERROR] Install jq"
    exit 1
  fi
  mkdir -p "$(dirname "$target")"
  token_secret="$($cluster_config kubectl get sa "$sa" -n "$namespace" -o json |
    jq -r '.secrets[].name | select(. | test(".*token.*"))')"
  current_cluster="$($cluster_config kubectl config view \
    -o jsonpath="{.contexts[?(@.name==\"$current_context\")].context.cluster}")"

  $cluster_config kubectl config set-credentials "$sa" --token="$(
    $cluster_config kubectl get secret "$token_secret" -n "$namespace" -o jsonpath="{.data.token}" \
    | base64 -d
  )" &>/dev/null
  $cluster_config kubectl config set-context "$sa_context" --user="$sa" --cluster="$current_cluster" &>/dev/null
  $cluster_config kubectl config use-context "$sa_context" &>/dev/null
  $cluster_config kubectl config view --flatten --minify >"$target"
  $cluster_config kubectl config use-context "$current_context" &>/dev/null
}

main() {
  parse_init "$@"

  CLUSTER_NAME="plnsvc"
  KCP_ENV="kcp-unstable"
  KUBECONFIG_KCP_ARGOCD="$KUBECONFIG_DIR/kcp.argocd-manager.yaml"
  KUBECONFIG_KCP_PLNSVC="$KUBECONFIG_DIR/kcp.plnsvc-manager.yaml"

  configure_kcp_cluster
  configure_pipeline_cluster
  register_clusters
  install_operators
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi
