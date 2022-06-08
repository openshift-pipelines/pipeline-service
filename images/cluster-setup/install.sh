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

usage() {

  printf "
Usage:
    %s [options]

Deploy Pipelines Service on the clusters as per the configuration in
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

exit_error() {
  printf "\n[ERROR] %s\n" "$@" >&2
  printf "Exiting script.\n"
  exit 1
}

# populate clusters with the cluster names taken from the kubeconfig
# populate contexts with the context name taken from the kubeconfig
# populate kubeconfigs with the associated kubeconfig for each cluster name
# only consider the first context for a specific cluster
get_clusters() {
    clusters=()
    contexts=()
    kubeconfigs=()
    printf "Extracting files under the kubeconfig dir and reading the content in each file \n"
    files=("$(ls "$WORKSPACE_DIR/gitops/sre/credentials/kubeconfig/compute")")
    for kubeconfig in "${files[@]}"; do
        printf "  - %s\n" "$kubeconfig"
        subs=("$(KUBECONFIG=${WORKSPACE_DIR}/gitops/sre/credentials/kubeconfig/compute/${kubeconfig} kubectl config view -o jsonpath='{range .contexts[*]}{.name}{","}{.context.cluster}{"\n"}{end}')")
        for sub in "${subs[@]}"; do
            context=$(echo -n "${sub}" | cut -d ',' -f 1)
            cluster=$(echo -n "${sub}" | cut -d ',' -f 2 | cut -d ':' -f 1)
            if ! (echo "${clusters[@]}" | grep "${cluster}"); then
                clusters+=( "${cluster}" )
                contexts+=( "${context}" )
                kubeconfigs+=( "${kubeconfig}" )
                printf "    - %s --- %s --- %s \n" "$cluster" "$context" "$kubeconfig"
            fi
        done
    done
    printf "\n"
}

switch_cluster() {
  # Sometimes the workspace is read-only, preventing the context switch
  export KUBECONFIG="/tmp/cluster.kubeconfig"
  cp "${WORKSPACE_DIR}/gitops/sre/credentials/kubeconfig/compute/${kubeconfigs[$i]}" "$KUBECONFIG"

  if ! kubectl config use-context "${contexts[$i]}" >/dev/null; then
    exit_error "\nCannot use '${contexts[$i]}' context in '$KUBECONFIG'."
  fi
}

install_tektoncd() {
  printf "Installing tektoncd components on the cluster via Openshift GitOps... \n"
  for i in "${!clusters[@]}"; do
    printf "  - %s:\n" "${clusters[$i]}"
    switch_cluster
    CONFIG_DIR=$(find "${WORKSPACE_DIR}/gitops/sre/environment/compute" -type d -name "${clusters[$i]}")
    kubectl apply -k "$CONFIG_DIR"
  done
  printf "\n"
}

wait_for_resource() {
  args=( "$@" )
  while ! kubectl get "${args[@]}" >/dev/null 2>/dev/null; do
    sleep 10
  done
}

wait_for_pod() {
  args=( "$@" )
  export -f wait_for_resource
  if ! timeout 20s bash -c "wait_for_resource pods ${args[*]}"; then
      exit_error "Pod not found."
  fi
  podname="$(kubectl get pods "${args[@]}" -o jsonpath='{.items[0].metadata.name}')"
  kubectl wait --for=condition=Ready "pod/$podname" -n openshift-pipelines --timeout=60s >/dev/null
}

postchecks() {
  printf "Checking deployment\n"
  #checking if the pipelines and triggers pods are up and running
  for i in "${!clusters[@]}"; do
    switch_cluster
    printf "  - %s:\n" "${clusters[$i]}"
    for pod in tekton-pipelines-controller tekton-triggers-controller tekton-triggers-core-interceptors; do
      printf "    - %s: " "$pod"
      wait_for_pod -n openshift-pipelines -l=app="$pod"
      printf "OK\n"
    done
  done
}

main() {
  parse_args "$@"
  get_clusters
  install_tektoncd
  postchecks
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi