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

usage() {
  printf "Usage:
    %s [options]

Bootstrap a new cluster so it can be managed by pipeline as code

Optional arguments:
    -k, --kubeconfig KUBECONFIG
        kubeconfig to the cluster has to be setup.
    -w, --work_dir WORK_DIR
        Directory into which the credentials folder will be created.
        Default: ./work
    -d, --debug
        Activate tracing/debug mode.
    -h, --help
        Display this message.

Example:
    %s -d -w /path/to/sre/repository/clone
" "${0##*/}" "${0##*/}" >&2
}

parse_args() {
  local args
  args="$(getopt -o dhw: -l "debug,help,work_dir" -n "$0" -- "$@")"
  eval set -- "$args"
  while true; do
    case "$1" in
    -k | --kubeconfig)
      shift
      KUBECONFIG="$1"
      export KUBECONFIG
      ;;
    -w | --work_dir)
      shift
      WORK_DIR="$1"
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
      printf "Unknown argument: %s\n" "$1" >&2
      usage
      exit 1
      ;;
    esac
    shift
  done
}

init() {
  WORK_DIR="${WORK_DIR:-$SCRIPT_DIR/work}"
  mkdir -p "$WORK_DIR"

  credentials_dir="$WORK_DIR/credentials/kubeconfig"
}

bootstrap_cluster() {
  case "$(kubectl config current-context)" in
  "workspace.kcp.dev/current") bootstrap_kcp ;;
  *) bootstrap_compute ;;
  esac

  printf "    - Create service account:\n"
  kubectl apply -f "$SCRIPT_DIR/manifests/pac-manager.yaml"

  printf "    - Generate kubeconfig: "
  get_context "pac-manager" "pipeline-as-code" "pac-manager" "$kubeconfig"
  printf "%s\n\n" "$kubeconfig"
}

bootstrap_kcp() {
  kcp_name="$(kubectl config view --minify -o json |
    jq ".clusters[0].cluster.server" |
    sed -r -e "s@.*://([^.]*).*@\1@").$(
    kubectl kcp workspace current | cut -d\" -f2 | cut -d: -f2- | tr ':' '.'
  )"
  printf "[KCP: %s\n]" "$kcp_name"
  kubeconfig="$credentials_dir/kcp/$kcp_name.yaml"
}

bootstrap_compute() {
  compute_name="$(kubectl config current-context | sed -r -e "s:-:.:g" -e "s@.*/([^.]*\.){2}(.*)(\.[^.]*){2}/.*@\2@")"
  printf "[Compute cluster: %s]\n" "$compute_name"
  kubeconfig="$credentials_dir/compute/$compute_name.yaml"
}

get_context() {
  # Helper function to generate a kubeconfig file for a service account
  local sa_context="$1"
  local namespace="$2"
  local sa="$3"
  local target="$4"
  local current_context
  current_context="$(kubectl config current-context)"

  if ! which jq &>/dev/null; then
    printf "[ERROR] Install jq\n" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$target")"
  token_secret="$(kubectl get sa "$sa" -n "$namespace" -o json |
    jq -r '.secrets[].name | select(. | test(".*token.*"))')"
  current_cluster="$(kubectl config view \
    -o jsonpath="{.contexts[?(@.name==\"$current_context\")].context.cluster}")"

  kubectl config set-credentials "$sa" --token="$(
    kubectl get secret "$token_secret" -n "$namespace" -o jsonpath="{.data.token}" |
      base64 -d
  )" &>/dev/null
  kubectl config set-context "$sa_context" --user="$sa" --cluster="$current_cluster" &>/dev/null
  kubectl config use-context "$sa_context" &>/dev/null
  kubectl config view --flatten --minify >"$target"
  kubectl config use-context "$current_context" &>/dev/null
}

main() {
  parse_args "$@"
  init
  bootstrap_cluster
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi
