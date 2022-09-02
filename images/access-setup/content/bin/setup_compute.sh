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

# shellcheck source=images/access-setup/content/bin/common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  printf "Usage:
    %s [options]

Generate access credentials for a new compute cluster so it can be managed by pipelines as code

Mandatory arguments:
    -k, --kubeconfig KUBECONFIG
        kubeconfig to the kcp instance to configure.
        The current context will be used.
        Default value: \$KUBECONFIG

Optional arguments:
    --kustomization KUSTOMIZATION
        path to the directory holding the kustomization.yaml to apply.
        Can be read from \$KUSTOMIZATION.
        Default: %s
    --git-remote-url GIT_URL
        Git repo to be referenced to apply various customizations.
        Can be read from \$GIT_URL.
        Default: %s
    --git-remote-ref GIT_REF
        Git repo's ref to be referenced to apply various customizations.
        Can be read from \$GIT_REF.
        Default: %s
    -w, --work-dir WORK_DIR
        Directory into which the credentials folder will be created.
    -d, --debug
        Activate tracing/debug mode.
    -h, --help
        Display this message.
Example:
    %s -d -k /path/to/compute.kubeconfig
" "${0##*/}" "$KUSTOMIZATION" "${0##*/}" >&2
}

parse_args() {
  KUSTOMIZATION=${KUSTOMIZATION:-github.com/openshift-pipelines/pipeline-service/gitops/compute/pac-manager?ref=main}
  GIT_URL=${GIT_URL:-"https://github.com/openshift-pipelines/pipeline-service.git"}
  GIT_REF=${GIT_REF:="main"}
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
    --git-remote-url)
      shift
      GIT_URL="$1"
      ;;
    --git-remote-ref)
      shift
      GIT_REF="$1"
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

  WORK_DIR=${WORK_DIR:-./work}
}

init() {
  WORK_DIR="${WORK_DIR:-$SCRIPT_DIR/work}"

  credentials_dir="$WORK_DIR/credentials/kubeconfig"
  mkdir -p "$credentials_dir"
}

check_prerequisites() {
  # Check that argocd has been installed
  if [[ $(kubectl api-resources | grep -c "argoproj.io/") = "0" ]]; then
    echo "Argo CD must be deployed on the cluster first" >&2
    exit 1
  fi
}

generate_compute_credentials() {
  current_context=$(kubectl config current-context)
  compute_name="$(yq '.contexts[] | select(.name == "'"$current_context"'") | .context.cluster' < "$KUBECONFIG" | sed 's/:.*//')"
  printf "[Compute cluster: %s]\n" "$compute_name"
  kubeconfig="$credentials_dir/compute/$compute_name.kubeconfig"

  printf "    - Create ServiceAccount for Pipelines as Code:\n"
  kubectl apply -k "$KUSTOMIZATION"

  printf "    - Generate kubeconfig: "
  get_context "pac-manager" "pipelines-as-code" "pac-manager" "$kubeconfig"
  printf "%s\n" "$kubeconfig"

  mkdir -p "$WORK_DIR/environment/compute/$compute_name"
  echo "resources:
  - $GIT_URL/gitops/argocd?ref=$GIT_REF
" >"$WORK_DIR/environment/compute/$compute_name/kustomization.yaml"
}

main() {
  parse_args "$@"
  prechecks
  init
  check_prerequisites
  generate_compute_credentials
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi
