#!/usr/bin/env bash

# Copyright 2022 The Pipeline Service Authors.
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

SCRIPT_DIR="$(
  cd "$(dirname "$0")" >/dev/null || exit 1
  pwd
)"

PROJECT_DIR="$(
  cd "$SCRIPT_DIR/../../../.." >/dev/null || exit 1
  pwd
)"
CKCP_DIR="$PROJECT_DIR/developer/ckcp"
GITOPS_DIR="$PROJECT_DIR/gitops"
CONFIG="$CKCP_DIR/config.yaml"

RESET_HARD="false"

usage() {
  printf "
Usage:
    %s [options]

Scrap ckcp and free resources deployed by openshift_dev_setup.sh script.

Mandatory arguments:
    --work-dir WORK_DIR
        Location of the cluster files related to the environment.
        A single file with extension kubeconfig is expected in the subdirectory: credentials/kubeconfig/kcp
        Kubeconfig files for compute clusters are expected in the subdirectory: credentials/kubeconfig/compute

Optional arguments:
    --reset-hard
        Aggressively remove operators deployed.
    -d, --debug
        Activate tracing/debug mode.
    -h, --help
        Display this message.

Example:
    %s --work-dir './tmp/tmp.435kjkdsf'
" "${0##*/}" "${0##*/}" >&2
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --work-dir)
      shift
      WORK_DIR="$1"
      ;;
    --reset-hard)
      shift
      RESET_HARD="true"
      ;;
    -d | --debug)
      set -x
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --)
      # End of arguments
      break
      ;;
    *)
      exit_error "Unknown argument: $1"
      ;;
    esac
    shift
  done
}

exit_error() {
    printf "[ERROR] %s" "$@" >&2
    usage
    exit 1
}


prechecks() {
    WORK_DIR=${WORK_DIR:-}
    if [[ -z "${WORK_DIR}" ]]; then
      printf "\n[ERROR] Missing parameter --work-dir" >&2
      exit 1
    fi
    KUBECONFIG="$WORK_DIR/credentials/kubeconfig/compute/compute.kubeconfig.base"
    if [ ! -f "$KUBECONFIG" ]; then
      printf "\n[ERROR] Couldn't find compute's kubeconfig." >&2
      printf "\nExpected compute's KUBECONFIG dir:'WORK_DIR/credentials/kubeconfig/compute/'"
      exit 1
    fi
    export KUBECONFIG="$KUBECONFIG"
    KCP_KUBECONFIG="$(find "$WORK_DIR/credentials/kubeconfig/kcp" -name \*.kubeconfig | head -1)"
    if [ ! -f "$KCP_KUBECONFIG" ]; then
      printf "\n[ERROR] Couldn't find the user's kcp workspace kubeconfig." >&2
      printf "\nExpected kcp KUBECONFIG dir:'WORK_DIR/credentials/kubeconfig/kcp'"
      exit 1
    fi
}

# Removes Argo CD applications deployed by openshift_dev_setup.sh
uninstall_pipeline_service() {
    printf "\n  Uninstalling Pipeline Service:\n"
    # Remove pipeline-service Argo CD application and
    # remove all the child applications deployed by Pipeline-Service
    if ! argocd app get pipeline-service >/dev/null 2>&1; then
      printf "\n[ERROR] Couldn't find the 'pipeline-service' application in argocd apps.\n" >&2
      exit 1
    fi
    argocd app delete pipeline-service --cascade --yes

    # Check if the Argo CD applications have been indeed removed
    # list of all the Argo Apps that a user can deploy using Pipeline Service
    mapfile -t all_argo_apps < <(kubectl kustomize "$GITOPS_DIR/argocd/argo-apps"  | yq '.metadata.name' | grep -v '^---$')
    all_argo_apps+=("pipeline-service")
    # list of all the Argo Apps still deployed
    mapfile -t argo_apps_deployed < <(argocd app list -o yaml | yq '.[].metadata.name')
    matched_apps=()
    for app in "${all_argo_apps[@]}"; do
        for deployed_app in "${argo_apps_deployed[@]}"; do
            if [ "$app" == "$deployed_app" ]; then
              matched_apps+=("$app")
            fi
        done
    done
    if (( ${#matched_apps[@]} >= 1 )); then
        printf "\n[ERROR] Couldn't uninstall deployed Argo CD applications:%s ${matched_apps[*]}" >&2
        exit 1
    fi
    printf "\nAll the Argo CD applications are successfully uninstalled.\n"
}

uninstall_operators(){
    printf "\n  Uninstalling Openshift-GitOps Operator:\n"
    kubectl delete -k "$CKCP_DIR/openshift-operators/openshift-gitops" --ignore-not-found=true
    openshift_gitops_csv=$(kubectl get csv -n openshift-operators | grep -ie "openshift-gitops-operator" | cut -d " " -f 1)
    if [[ -n "$openshift_gitops_csv" ]]; then
      kubectl delete csv -n openshift-operators "$openshift_gitops_csv"
    fi
    mapfile -t argo_crds < <(kubectl get crd | grep -iE "argoproj.io|gitopsservices" | cut -d " " -f 1)
    if [[ "${#argo_crds[@]}" -gt 0 ]]; then
      for crd in "${argo_crds[@]}"; do
        kubectl delete crd "$crd" &
        kubectl patch crd "$crd" --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' >/dev/null 2>&1
        wait
      done
    fi
    gitops_operator=$(kubectl get operator | grep -ie "gitops-operator" | cut -d " " -f 1)
    if [[ -n "$gitops_operator" ]]; then
      kubectl delete operator "$gitops_operator"
    fi

    printf "\n  Uninstalling PAC Controllers:\n"
    kubectl delete -k "$GITOPS_DIR/pac/manifests" --ignore-not-found=true
    pac_ns=$(kubectl get ns | grep -ie "pipelines-as-code" | cut -d " " -f 1)
    if [[ -n "$pac_ns" ]]; then
      kubectl delete ns "$pac_ns"
    fi

    printf "\n  Uninstalling Openshift-Pipelines Operator:\n"
    # We start with deleting tektonconfig so that the 'tekton.dev' CRs are removed gracefully by it.
    kubectl delete tektonconfig config
    kubectl delete -k "$GITOPS_DIR/argocd/tektoncd" --ignore-not-found=true
    openshift_pipelines_csv=$(kubectl get csv -n openshift-operators | grep -ie "openshift-pipelines-operator" | cut -d " " -f 1)
    if [[ -n "$openshift_pipelines_csv" ]]; then
      kubectl delete csv -n openshift-operators "$openshift_pipelines_csv"
    fi
    mapfile -t tekton_crds < <(kubectl get crd | grep -ie "tekton.dev" | cut -d " " -f 1)
    if [[ "${#tekton_crds[@]}" -gt 0 ]]; then
      for crd in "${tekton_crds[@]}"; do
        kubectl delete crd "$crd" &
        kubectl patch crd "$crd" --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' >/dev/null 2>&1
        wait
      done
    fi
    openshift_pipelines_operator=$(kubectl get operator | grep -ie "openshift-pipelines-operator" | cut -d " " -f 1)
    if [[ -n "$openshift_pipelines_operator" ]]; then
      kubectl delete operator "$openshift_pipelines_operator"
    fi

    # Checks if the operators are uninstalled successfully
    mapfile -t operators < <(kubectl get operators | grep -iE "openshift-gitops-operator|openshift-pipelines-operator" | cut -d " " -f 1)
    if (( ${#operators[@]} >= 1 )); then
        printf "\n[ERROR] Couldn't uninstall all Operators, please try removing them manually." >&2
        exit 1
    fi
    printf "\nAll the operators are successfully uninstalled.\n"
}

# Cleans ckcp deployed resources from the cluster
uninstall_ckcp(){
    # Extract label from synctargets inside the kcp user workspace to be able to select namespaces
    # created in the compute cluster by the same kcp-workspace.
    ns_label=$(KUBECONFIG=${KCP_KUBECONFIG} kubectl get synctargets.workload.kcp.dev -o yaml | yq '.items[0].metadata.labels' | grep -ie "internal.workload.kcp.dev/key")
    if [[ -z $ns_label ]]; then
        printf "\n[ERROR] Couldn't extract labels from kcp synctarget object.\n" >&2
        printf "\nMake sure you pass the correct directory for fetching user's kcp workspace credentials using --work-dir arg\n"
        exit 1
    fi

    # remove resources created by ckcp
    printf "\n  Uninstalling ckcp from the cluster:\n"
    kubectl delete -k "$CKCP_DIR/openshift/overlays/dev" --ignore-not-found=true
    # Check if the ckcp pod is removed from the compute cluster
    mapfile -t ckcp_pod < <(kubectl get pods -n ckcp -l "app=kcp-in-a-pod" | cut -d " " -f 1 | tail -n +2)
    if (( ${#ckcp_pod[@]} >= 1  )); then
        printf "\n[ERROR] Couldn't remove the ckcp pods: %s ${ckcp_pod[*]}" >&2
        exit 1
    fi

    # remove syncer resources
    printf "\n  Removing resources created by the syncer:\n"
    current_context="$(yq e ".current-context" <"$KUBECONFIG")"
    current_context=$(echo "$current_context" | sed 's,default/,,g; s,:6443/kube:admin,,g')
    syncer_manifest=/tmp/syncer-"$current_context".yaml
    if [ ! -f "$syncer_manifest" ]; then
      printf "\n[ERROR] Couldn't find syncer manifest." >&2
      printf "\nExpected syncer manifest dir:'%s'" "$syncer_manifest"
      exit 1
    fi
    kubectl delete -f "$syncer_manifest" --ignore-not-found=true

    # remove namesapces created by ckcp
    printf "\n  Removing namespaces created by ckcp:\n"
    mapfile -t ckcp_generated_ns < <(kubectl get ns -l "${ns_label//\/key: /\/cluster=}" | cut -d " " -f 1 | tail -n +2)
    for ns in "${ckcp_generated_ns[@]}"; do
        printf " - %s\n" "$ns"
        kubectl delete ns "$ns"
    done

    # Check if the namespaces created by ckcp are removed
    for i in {1..7}; do
      mapfile -t ckcp_generated_ns < <(kubectl get ns -l "${ns_label//\/key: /\/cluster=}" | cut -d " " -f 1 | tail -n +2)
      if (( i == 7 )); then
        printf "\n[ERROR] Couldn't remove the namespaces created by ckcp: %s ${ckcp_generated_ns[*]}" >&2
        exit 1
      elif (( ${#ckcp_generated_ns[@]} >= 1  )); then
        sleep 5
      else
        break
      fi
    done
    printf "\nckcp reset successful.\n"
}

main(){
    parse_args "$@"
    prechecks
    APPS=()
    read -ra APPS <<< "$(yq eval '.apps | join(" ")' "$CONFIG")"
    for app in "${APPS[@]}"; do
        "uninstall_$app"
    done

    uninstall_ckcp

    if [ "$(echo "$RESET_HARD" | tr "[:upper:]" "[:lower:]")" == "true" ] || [ "$RESET_HARD" == "1" ]; then
      uninstall_operators
    fi
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
    main "$@"
fi
