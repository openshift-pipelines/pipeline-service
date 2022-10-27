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

# shellcheck source=operator/images/cluster-setup/bin/utils.sh
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
}

install_clusters() {
  export KUBECONFIG="/tmp/cluster.kubeconfig"
  for i in "${!clusters[@]}"; do
    printf "[Compute %s:\n" "${clusters[$i]}]"
    switch_cluster | indent 2

    printf -- "- Installing shared manifests... \n"
    install_shared_manifests | indent 4
    printf -- "- Installing applications via Openshift GitOps... \n"
    install_applications | indent 4

    #checking if the pipelines and triggers pods are up and running
    printf -- "- Checking deployment status\n"
    tektonDeployments=("tekton-pipelines-controller" "tekton-triggers-controller" "tekton-triggers-core-interceptors")
    check_deployments "openshift-pipelines" "${tektonDeployments[@]}" | indent 4
    certManagerDeployments=("tekton-chains-controller")
    check_deployments "tekton-chains" "${certManagerDeployments[@]}" | indent 4
    certManagerDeployments=("cert-manager" "cert-manager-cainjector" "cert-manager-webhook")
    check_deployments "openshift-cert-manager" "${certManagerDeployments[@]}" | indent 4
  done
}

install_shared_manifests() {
  if [ "$(kubectl get secret -n tekton-chains signing-secrets --ignore-not-found -o json | jq -r ".immutable")" != "true" ]; then
    kubectl apply -f "$WORKSPACE_DIR/credentials/manifests/compute/tekton-chains/signing-secrets.yaml"
  fi
  kubectl apply -f "$WORKSPACE_DIR/credentials/manifests/compute/tekton-results/tekton-results-secret.yaml"
}

install_applications() {
  CONFIG_DIR=$(find "${WORKSPACE_DIR}/environment/compute" -type d -name "${clusters[$i]}")
  kubectl apply -k "$CONFIG_DIR"
}

main() {
  parse_args "$@"
  get_clusters
  install_clusters
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi
