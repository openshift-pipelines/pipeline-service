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

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(
  cd "$(dirname "$0")" >/dev/null
  pwd
)"

# shellcheck source=operator/images/cluster-setup/content/bin/utils.sh
source "$SCRIPT_DIR/utils.sh"

usage() {

  printf "
Usage:
    %s [options]

Deploy Pipeline Service on the clusters as per the configuration in
WORKSPACE_DIR.

Optional arguments:
    -w, --workspace-dir WORKSPACE_DIR
        Location of the folder holding the clusters configuration.
        Default: \$WORKSPACE_DIR or current directory if the environment
        variable is unset.
    -d, --debug
        Activate tracing/debug mode.
    -h, --help
        Display this message.

Example:
    %s --workspace_dir WORKSPACE_DIR
" "${0##*/}" "${0##*/}" >&2
}

parse_args() {
  WORKSPACE_DIR="${WORKSPACE_DIR:-$PWD}"

  while [[ $# -gt 0 ]]; do
    case $1 in
    -w | --workspace-dir)
      shift
      WORKSPACE_DIR="$1"
      ;;
    -d | --debug)
      DEBUG="--debug"
      set -x
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
    esac
    shift
  done
  DEBUG="${DEBUG:-}"
}

# populate clusters with the cluster names taken from the kubeconfig
# populate contexts with the context name taken from the kubeconfig
# populate kubeconfigs with the associated kubeconfig for each cluster name
# only consider the first context for a specific cluster
get_clusters() {
    clusters=()
    contexts=()
    kubeconfigs=()
    mapfile -t files < <(find "$WORKSPACE_DIR/credentials/kubeconfig/compute/" -name \*.kubeconfig)
    for kubeconfig in "${files[@]}"; do
        mapfile -t subs < <(KUBECONFIG=${kubeconfig} kubectl config view -o jsonpath='{range .contexts[*]}{.name}{","}{.context.cluster}{"\n"}{end}')
        for sub in "${subs[@]}"; do
            context=$(echo -n "${sub}" | cut -d ',' -f 1)
            cluster=$(echo -n "${sub}" | cut -d ',' -f 2 | cut -d ':' -f 1)
            if ! (echo "${clusters[@]}" | grep "${cluster}"); then
                clusters+=( "${cluster}" )
                contexts+=( "${context}" )
                kubeconfigs+=( "${kubeconfig}" )
            fi
        done
    done
}

switch_cluster() {
  # Sometimes the workspace is read-only, preventing the context switch
  cp "${kubeconfigs[$i]}" "$KUBECONFIG"

  if ! kubectl config use-context "${contexts[$i]}" >/dev/null; then
    exit_error "\nCannot use '${contexts[$i]}' context in '$KUBECONFIG'."
  fi

  # Check that argocd has been installed
  if [[ $(kubectl api-resources | grep -c "argoproj.io/") = "0" ]]; then
    echo "[ERROR] Argo CD must be deployed on the cluster for kubeconfig/context: '${kubeconfigs[$i]}'/'${contexts[$i]}'" >&2
    exit 1
  fi
}

install_clusters() {
  export KUBECONFIG="/tmp/cluster.kubeconfig"
  for i in "${!clusters[@]}"; do
    switch_cluster | indent 2

    printf -- "- Installing shared manifests... \n"
    install_shared_manifests | indent 4

    printf -- "- Installing applications via Openshift GitOps... \n"
    install_applications | indent 4

    printf -- "- Checking application status\n"
    check_applications "openshift-gitops" "pipeline-service" | indent 4

    printf -- "- Checking subscription status\n"
    check_subscriptions "openshift-operators" "openshift-pipelines-operator" | indent 4

    #checking if the pipelines and triggers pods are up and running
    printf -- "- Checking deployment status\n"
    tektonDeployments=("tekton-pipelines-controller" "tekton-triggers-controller" "tekton-triggers-core-interceptors" "tekton-chains-controller")
    check_deployments "openshift-pipelines" "${tektonDeployments[@]}" | indent 4
    resultsDeployments=("tekton-results-api" "tekton-results-watcher")
    check_deployments "tekton-results" "${resultsDeployments[@]}" | indent 4
    resultsStatefulsets=("postgres-postgresql" "minio-pool-0")
    check_statefulsets "tekton-results" "${resultsStatefulsets[@]}" | indent 4

    printf -- "- Checking pods status for controlplane namespaces\n"
    # list of control plane namespaces
    CONTROL_PLANE_NS=("openshift-apiserver" "openshift-controller-manager" "openshift-etcd" "openshift-ingress" "openshift-kube-apiserver" "openshift-kube-controller-manager" "openshift-kube-scheduler")
    for ns in "${CONTROL_PLANE_NS[@]}"; do
      check_crashlooping_pods "$ns" | indent 4
    done
  done
}

install_shared_manifests() {
  CREDENTIALS_DIR="$WORKSPACE_DIR/credentials"

  # if [ "$(kubectl get secret -n tekton-chains signing-secrets --ignore-not-found -o json | jq -r ".immutable")" != "true" ]; then
  #   kubectl apply -k "$CREDENTIALS_DIR/manifests/compute/tekton-chains"
  # fi
  kubectl apply -k "$CREDENTIALS_DIR/manifests/compute/tekton-results"
}

install_applications() {
  CONFIG_DIR=$(find "${WORKSPACE_DIR}/environment/compute" -type d -name "${clusters[$i]}")
  kubectl apply -k "$CONFIG_DIR"
}

main() {
  parse_args "$@"
  fetch_bitwarden_secrets
  get_clusters
  INSTALL_FAILED=0
  install_clusters
  exit "$INSTALL_FAILED"
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi
