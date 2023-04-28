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
  cd "$SCRIPT_DIR/../.." >/dev/null || exit 1
  pwd
)"
DEV_DIR="$PROJECT_DIR/developer/openshift"
GITOPS_DIR="$PROJECT_DIR/operator/gitops/argocd/pipeline-service"
COMPUTE_DIR="$PROJECT_DIR/operator/gitops/compute/pipeline-service-manager"

usage() {
  printf "
Usage:
    %s [options]

Scrap local Pipeline-Service environment and free resources deployed by dev_setup.sh script.

Mandatory arguments:
    --work-dir WORK_DIR
        Location of the cluster files related to the environment.
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

  RESET_HARD=${RESET_HARD:-}
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
}

check_if_argocd_app_was_removed() {
  local appName=$1
  local numOfAttempts=$2
  local i=0
  printf "Removing ArgoCD application '%s': " "$appName"
  while argocd app get "${appName}" >/dev/null 2>&1; do
    printf '.'; sleep 10;
    i=$((i+1))
    if [[ $i -eq "${numOfAttempts}" ]]; then
      printf "\n[ERROR] ArgoCD app %s was no deleted by timeout \n" "$appName" >&2
      printf "The deletion process might be taking longer than expected. You can wait a minute or two and execute the script again."
      printf "If it is still failing, try to run the script again with the '--reset-hard' option."
      exit 1
    fi
  done
  printf " OK\n"
}

uninstall_pipeline_service_storage() {
    printf "\nUninstalling Pipeline Service Storage:\n"
    if argocd app get pipeline-service-storage >/dev/null 2>&1; then

      # If something went wrong(e.g. bad development changes) the ArgoCD sync operation can be very long or could hang.
      # In this case any other ArgoCD operation will be queued.
      # Therefore the 'delete' operation will not be executed in a timely manner.
      # Cancelling the sync operation speeds up the process.
      argocd app terminate-op pipeline-service-storage >/dev/null 2>&1

      argocd app delete pipeline-service-storage --yes

      if [ -n "${RESET_HARD}" ]; then
        # Remove any finalizers that might inhibit deletion
        if argocd app get pipeline-service-storage >/dev/null 2>&1; then
          kubectl patch applications.argoproj.io -n openshift-gitops pipeline-service-storage --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' >/dev/null 2>&1
        fi

        # Check if the Argo CD application has been indeed removed
        if argocd app get pipeline-service-storage >/dev/null 2>&1; then
          printf "\n[ERROR] Couldn't uninstall Pipeline Service Storage Argo CD application." >&2
          exit 1
        fi

        printf "\nUninstalling Pipeline Service Storage:\n"
        kubectl delete -k "$DEV_DIR/gitops/argocd/pipeline-service-storage" --ignore-not-found=true
      else
        check_if_argocd_app_was_removed "pipeline-service-storage" 100
      fi

      printf "\nRemoving Minio Operator:\n"
      minio_gitops_csv=$(kubectl get csv -n openshift-operators | grep -ie "minio-operator" | cut -d " " -f 1)
      if [[ -n "$minio_gitops_csv" ]]; then
        kubectl delete csv -n openshift-operators "$minio_gitops_csv"
      fi

      mapfile -t minio_crds < <(kubectl get crd -n openshift-operators | grep -iE "tenant" | cut -d " " -f 1)
      if [[ "${#minio_crds[@]}" -gt 0 ]]; then
        for crd in "${minio_crds[@]}"; do
          printf "\nDelete crd %s\n" "$crd"
          kubectl delete crd "$crd"
        done
      fi

      minio_operator=$(kubectl get operator | grep -ie "minio" | cut -d " " -f 1)
      if [[ -n "$minio_operator" ]]; then
        printf "\nDelete operator cr %s\n" "$minio_operator"
        kubectl delete operator "$minio_operator"
      fi
    fi

    printf "\n[INFO] Pipeline-Service-Storage Argo CD application has been successfully removed.\n"
}

uninstall_pipeline_service_monitoring() {
    printf "\nUninstalling Pipeline Service Monitoring:\n"
    if argocd app get pipeline-service-o11y >/dev/null 2>&1; then

      # If something went wrong(e.g. bad development changes) the ArgoCD sync operation can be very long or could hang.
      # In this case any other ArgoCD operation will be queued.
      # Therefore the 'delete' operation will not be executed in a timely manner.
      # Cancelling the sync operation speeds up the process.
      argocd app terminate-op pipeline-service-o11y >/dev/null 2>&1

      argocd app delete pipeline-service-o11y --yes

      if [ -n "${RESET_HARD}" ]; then
        # Remove any finalizers that might inhibit deletion
        if argocd app get pipeline-service-o11y >/dev/null 2>&1; then
          kubectl patch applications.argoproj.io -n openshift-gitops pipeline-service-o11y --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' >/dev/null 2>&1
        fi

        # Check if the Argo CD application has been indeed removed
        if argocd app get pipeline-service-o11y >/dev/null 2>&1; then
          printf "\n[ERROR] Couldn't uninstall Pipeline Service O11y Argo CD application." >&2
          exit 1
        fi

        printf "\nUninstalling Pipeline Service Monitoring:\n"
        kubectl delete -k "$DEV_DIR/gitops/argocd/pipeline-service-o11y" --ignore-not-found=true
      else
        check_if_argocd_app_was_removed "pipeline-service-o11y" 100
      fi
    fi

    printf "\n[INFO] Pipeline-Service-Monitoring Argo CD application has been successfully removed.\n"
}

uninstall_pipeline_service() {
    printf "\nUninstalling Pipeline Service:\n"
    # Remove pipeline-service Argo CD application
    if [ -z "$RESET_HARD" ]; then
      if ! argocd app get pipeline-service >/dev/null 2>&1; then
        printf "\n[ERROR] Couldn't find the 'pipeline-service' application in argocd apps.\n" >&2
        exit 1
      fi
    fi

    # Remove tektonconfig and finalizers
    argocd app delete-resource pipeline-service --orphan --force --kind "TektonConfig" --resource-name "config" >/dev/null 2>&1
    kubectl patch tektonconfigs.operator.tekton.dev config --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' >/dev/null 2>&1

    # If something went wrong(e.g. bad development changes) the ArgoCD sync operation can be very long or could hang.
    # In this case any other ArgoCD operation will be queued.
    # Therefore the 'delete' operation will not be executed in a timely manner.
    # Cancelling the sync operation speeds up the process.
    argocd app terminate-op pipeline-service >/dev/null 2>&1

    argocd app delete pipeline-service --yes

    if [ -n "$RESET_HARD" ]; then
      # Remove any finalizers that might inhibit deletion
      if argocd app get pipeline-service >/dev/null 2>&1; then
        kubectl patch applications.argoproj.io -n openshift-gitops pipeline-service --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' >/dev/null 2>&1
      fi

      # Check if the Argo CD application has been indeed removed
      if argocd app get pipeline-service >/dev/null 2>&1; then
        printf "\n[ERROR] Couldn't uninstall Pipeline-Service Argo CD application." >&2
        exit 1
      fi
    else
      check_if_argocd_app_was_removed "pipeline-service" 100
    fi

    # Remove pipeline-service-manager resources
    kubectl delete -k "$COMPUTE_DIR" --ignore-not-found=true

    printf "\n[INFO] Pipeline-Service Argo CD application has been successfully removed.\n"
}

uninstall_operators_and_controllers(){
    printf "\nUninstalling Openshift-GitOps Operator:\n"
    kubectl delete -k "$DEV_DIR/operators/openshift-gitops" --ignore-not-found=true
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

    oc delete project openshift-gitops

    gitops_operator=$(kubectl get operator | grep -ie "gitops-operator" | cut -d " " -f 1)
    if [[ -n "$gitops_operator" ]]; then
      kubectl delete operator "$gitops_operator"
    fi

    printf "\n  Uninstalling tekton-results:\n"
    kubectl delete -k "$GITOPS_DIR/tekton-results" --ignore-not-found=true
    tkn_results_ns=$(kubectl get ns | grep -ie "tekton-results" | cut -d " " -f 1)
    if [[ -n "$pac_ns" ]]; then
      kubectl delete ns "$tkn_results_ns"
    fi

    # Checks if the operators are uninstalled successfully
    mapfile -t operators < <(kubectl get operators | grep -iE "openshift-gitops-operator" | cut -d " " -f 1)
    if (( ${#operators[@]} >= 1 )); then
        printf "\n[ERROR] Couldn't uninstall gitops operator, please try removing it manually." >&2
        exit 1
    fi

    # Checks if the Tekton controllers are uninstalled successfully
    mapfile -t controllers < <(kubectl get ns | grep -iE "tekton-results" | cut -d " " -f 1)
    if (( ${#controllers[@]} >= 1 )); then
        printf "\n[ERROR] Couldn't remove Tekton controllers, please try removing them manually." >&2
        exit 1
    fi

    printf "\n[INFO] Gitops operator and Tekton controllers are successfully uninstalled.\n"
}

# ArgoCD installs openshift pipelines operator with "pipeline-service" ArgoCD application
# with help of operator subscription.
# reset.sh script with disabled "reset-hard" mode removes only operator subscription 
# when ArgoCD application was deleted.
# So the uninstallation is not complete, we still have remaining operator resources created by OLM.
# We need to clean up these resources to make the certified CatalogSource healthy. 
# A CatalogSource with unhealthy status prevents installation of more operators.
uninstallOpenshiftPipelines() {
    printf "\nUninstalling Openshift-Pipelines Operator:\n"
    # We start with deleting tektonconfig so that the 'tekton.dev' CRs are removed gracefully by it.
    kubectl delete tektonconfig config --ignore-not-found=true
    if [ -n "$RESET_HARD" ]; then
      # We start with deleting tektonconfig so that the 'tekton.dev' CRs are removed gracefully by it.
      kubectl delete -k "$GITOPS_DIR/openshift-pipelines" --ignore-not-found=true
    fi

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

    # When "reset-hard" mode disabled, we don't remove gitops operator.
    # That's ok, but in this case we can't delete "operators.operators.coreos.com" objects
    # for another operators. Because OLM re-create them...
    # This issue isn't critical and don't break re-installation flow.
    # todo: investigate reason and fix it.
    if [ -n "${RESET_HARD}" ]; then
      # Checks if the operator are uninstalled successfully
      mapfile -t operators < <(kubectl get operators | grep -iE "openshift-pipelines-operator" | cut -d " " -f 1)
      if (( ${#operators[@]} >= 1 )); then
        printf "\n[ERROR] Couldn't uninstall operators, please try removing them manually." >&2
        exit 1
      fi
    fi
}

main(){
    parse_args "$@"
    prechecks
    uninstall_pipeline_service_storage
    uninstall_pipeline_service_monitoring
    uninstall_pipeline_service

    if [ -n "${RESET_HARD}" ]; then
      uninstall_operators_and_controllers
    fi

    uninstallOpenshiftPipelines
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
    main "$@"
    printf "\n[INFO] Uninstallation pipeline-service was completed.\n"
fi
