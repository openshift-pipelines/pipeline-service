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

# shellcheck source=operator/images/access-setup/content/bin/common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  printf "Usage:
    %s [options]

Generate access credentials in order to manage cluster via gitops tools

Mandatory arguments:
    -k, --kubeconfig KUBECONFIG
        kubeconfig to the compute instance to configure.
        The current context will be used.
        Default value: \$KUBECONFIG

Optional arguments:
    --kustomization KUSTOMIZATION
        path to the directory holding the kustomization.yaml to create Pipeline Service SA.
        Can be read from \$KUSTOMIZATION.
        Default: %s
    -w, --work-dir WORK_DIR
        Directory into which the credentials folder will be created.
    -d, --debug
        Activate tracing/debug mode.
    -h, --help
        Display this message.
Example:
    %s -d -k /path/to/compute.kubeconfig
" "${0##*/}" "$KUSTOMIZATION"  "${0##*/}" >&2
}

parse_args() {
  KUSTOMIZATION=${KUSTOMIZATION:-github.com/openshift-pipelines/pipeline-service/operator/gitops/compute/pipeline-service-manager?ref=main}

  while [[ $# -gt 0 ]]; do
    case "$1" in
    -k | --kubeconfig)
      shift
      KUBECONFIG="$1"
      ;;
    --kustomization)
      shift
      KUSTOMIZATION="$1"
      ;;
    -w | --work-dir)
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
      exit_error "Unknown argument: $1"
      ;;
    esac
    shift
  done
}

prechecks() {
  KUBECONFIG=${KUBECONFIG:-}
  if [[ -z "${KUBECONFIG}" ]]; then
    exit_error "Missing parameter --kubeconfig"
  fi
  if [[ ! -f "$KUBECONFIG" ]]; then
    echo "File not found: $KUBECONFIG" >&2
    exit 1
  fi
  export KUBECONFIG
}

init() {
  WORK_DIR="${WORK_DIR:-$SCRIPT_DIR/work}"
  credentials_dir="$WORK_DIR/credentials/kubeconfig"
  mkdir -p "$credentials_dir"
}

generate_compute_credentials() {
  current_context=$(kubectl config current-context)
  compute_name="$(yq '.contexts[] | select(.name == "'"$current_context"'") | .context.cluster' < "$KUBECONFIG" | sed 's/:.*//')"
  kubeconfig="$credentials_dir/compute/$compute_name.kubeconfig"

  printf -- "- Create ServiceAccount for Pipeline Service:\n"
  kubectl apply -k "$KUSTOMIZATION" | indent 4

  printf -- "- Generate kubeconfig:\n"
  get_context "pipeline-service-manager" "pipeline-service" "pipeline-service-manager" "$kubeconfig"
  printf "KUBECONFIG=%s\n" "$kubeconfig" | indent 4
}

main() {
  parse_args "$@"
  prechecks
  init
  generate_compute_credentials
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi
