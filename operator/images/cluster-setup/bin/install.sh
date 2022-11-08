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

fetch_bitwarden_secrets() {
  CREDENTIALS_DIR="$WORKSPACE_DIR/credentials"
  BITWARDEN_CRED="$CREDENTIALS_DIR/secrets/bitwarden.yaml"

  BW_CLIENTID="${BW_CLIENTID:-}"
  BW_CLIENTSECRET="${BW_CLIENTSECRET:-}"
  BW_PASSWORD="${BW_PASSWORD:-}"

  if [ ! -e "$BITWARDEN_CRED" ]; then
    return
  fi

  printf "[Bitwarden]:\n "
  printf "bitwarden.yaml file exists. Checking if the required variables to connect to Bitwarden are set.\n" | indent 2
  if [ -z "$BW_PASSWORD" ]; then
      printf "Please set the required env variables and try again.\n" >&2 | indent 2
      return
  fi

  printf "Required variables are available.\n" | indent 2
  if [ "$(bw logout >/dev/null 2>&1)$?" -eq 0 ]; then
    printf "Logout successful.\n" >/dev/null
  fi
  if [ "$(BW_CLIENTID="$BW_CLIENTID" BW_CLIENTSECRET="$BW_CLIENTSECRET" bw login --apikey >/dev/null 2>&1)$?" -eq 0 ]; then
    printf "Login successful.\n" >/dev/null
  fi

  login_status=$(bw login --check 2>&1)
  if [ "$login_status" = "You are not logged in." ]; then
    printf "Error while logging into Bitwarden.\n" >&2 | indent 2
    return
  fi

  session=$(BW_PASSWORD="$BW_PASSWORD" bw unlock --passwordenv BW_PASSWORD --raw)

  # process id/path pairs from bitwarden.yaml
  secret_count=$(yq '.credentials | length' "$BITWARDEN_CRED")
  for i in $(seq 0 "$((secret_count-1))")
  do
    content=$(bw get password "$(yq ".credentials[$i].id" "$BITWARDEN_CRED")" --session "$session")
    path=$(yq ".credentials[$i].path" "$BITWARDEN_CRED")

    if ! mkdir -p "$(dirname "$WORKSPACE_DIR/$path")" 2>/dev/null; then
      printf "Unable to create the folder. Exiting.\n" >&2 | indent 2
      exit 1
    fi
    if ! echo "$content" | base64 -d > "$WORKSPACE_DIR/$path"; then
      printf "Unable to copy the contents of the secret to the specified path. Exiting.\n" >&2 | indent 2
      exit 1
    fi
  done
  printf "Extracted secrets from Bitwarden and substituted them in the relevant files.\n" | indent 2
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
  CREDENTIALS_DIR="$WORKSPACE_DIR/credentials"

  if [ "$(kubectl get secret -n tekton-chains signing-secrets --ignore-not-found -o json | jq -r ".immutable")" != "true" ]; then
    kubectl apply -k "$CREDENTIALS_DIR/manifests/compute/tekton-chains"
  fi
  kubectl apply -k "$CREDENTIALS_DIR/manifests/compute/tekton-results"
}

install_applications() {
  CONFIG_DIR=$(find "${WORKSPACE_DIR}/environment/compute" -type d -name "${clusters[$i]}")
  kubectl apply -k "$CONFIG_DIR"
}

main() {
  parse_args "$@"
  get_clusters
  fetch_bitwarden_secrets
  install_clusters
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi
