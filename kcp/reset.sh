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
  cd "$(dirname "$0")" >/dev/null
  pwd
)"

source "$SCRIPT_DIR/common.sh"

usage(){
  echo "Usage:
    ${0##*/} [options]

Reset all the configuration for pipelines service" >&2
  usage_args
}

reset_argocd() {
  echo "[ArgoCD]"

  echo -n "  - Removing applications: "
  for app in pipelines-controller pipelines-crds triggers-controller triggers-crds \
    triggers-interceptors; do
      if argocd_local app get $app >/dev/null 2>&1; then
        argocd_local app delete $app -y --cascade=false >/dev/null &
      fi
  done
  wait
  echo "OK"

  echo -n "  - Removing clusters: "
  # `argocd cluster rm` is failing with `permission denied`
  # The workaround is to delete the secret to the cluster
  for secret in $(
    plnsvc_config kubectl get secrets -n openshift-gitops | \
    grep -E "^cluster-[^ ]+-[0-9]*" --only-matching
  ); do
    plnsvc_config kubectl delete secret "$secret" -n openshift-gitops --wait >/dev/null &
  done
  wait
  echo "OK"

  echo
}

reset_kcp() {
  echo "[KCP]"

  echo -n "  - Removing cluster-scoped resources: "
  for resource in \
    clusterrole.rbac.authorization.k8s.io/plnsvc-admin \
    $(
    kcp_config kubectl get clusterrolebindings,workloadcluster 2>/dev/null | \
    grep / | cut -d\  -f1
  ); do
    kcp_config kubectl delete "$resource" \
      --ignore-not-found --wait >/dev/null
  done
  echo "OK"

  echo -n "  - Removing plnsvc namespace: "
  # Hold the accounts to the plnsvc cluster
  kcp_config kubectl delete namespace plnsvc \
    --ignore-not-found --wait >/dev/null
  echo "OK"

  echo -n "  - Removing service account for ArgoCD: "
  tail -n +6 "$SCRIPT_DIR/manifests/kcp/argocd-manager.yaml" | \
    kcp_config kubectl delete -f - --ignore-not-found --wait >/dev/null
  echo "OK"

  echo -n "  - Removing CRDs: "
  for crd in $(kcp_config kubectl get crds --no-headers 2>/dev/null | cut -d\  -f1); do
    kcp_config kubectl delete crds "$crd" --wait >/dev/null &
  done
  wait
  echo "OK"

  echo -n "  - Removing tekton-pipelines namespace: "
  kcp_config kubectl delete namespace tekton-pipelines --ignore-not-found --wait >/dev/null
  echo "OK"

  echo
}

reset_plnsvc() {
  echo "[Pipeline cluster]"

  echo -n "  - Removing KCP service account: "
  plnsvc_config kubectl delete -f "$SCRIPT_DIR/manifests/plnsvc/kcp-manager.yaml" \
    --ignore-not-found --wait >/dev/null
  echo "OK"


  echo -n "  - Removing kcp namespaces: "
  plnsvc_config kubectl delete -f "$SCRIPT_DIR/manifests/plnsvc/namespace.yaml" \
    --ignore-not-found --wait >/dev/null &
  for ns in $(
    plnsvc_config kubectl get ns | grep -E "^kcp(sync)?[0-9a-z]{56}" --only-matching |
    cut -d\  -f1); do
    plnsvc_config kubectl delete namespace "$ns" --ignore-not-found --wait >/dev/null &
  done
  wait
  echo "OK"

  echo
}

main() {
  parse_init "$@"
  reset_argocd
  reset_kcp
  reset_plnsvc
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi
