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

Generate access credentials for a new KCP instance so it can be managed by pipelines as code

Mandatory arguments:
    -k, --kubeconfig KUBECONFIG
        kubeconfig to the kcp instance to configure.
        The current context will be used.
        Default value: \$KUBECONFIG

Optional arguments:
    --kcp-org KCP_ORG
        Path to the organization workspace.
        Can be read from \$KCP_ORG.
        Default value: Workspace in use by the current context.
    --kcp-workspace KCP_WORKSPACE
        Name of the workspace in which the compute clusters will be registered.
        Can be read from \$KCP_WORKSPACE.
        Default: compute
    --kustomization KUSTOMIZATION
        path to the directory holding the kustomization.yaml to apply.
        Can be read from \$KUSTOMIZATION.
        Default: %s
    -w, --work-dir WORK_DIR
        Directory into which the credentials folder will be created.
        Default: ./work
    -d, --debug
        Activate tracing/debug mode.
    -h, --help
        Display this message.

Example:
    %s -d -k /path/to/kcp.kubeconfig
" "${0##*/}" "$KUSTOMIZATION" "${0##*/}" >&2
}

parse_args() {
  KUSTOMIZATION=${KUSTOMIZATION:-github.com/openshift-pipelines/pipeline-service/operator/gitops/kcp/pipeline-service-manager?ref=main}
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -k | --kubeconfig)
      shift
      KUBECONFIG="$1"
      ;;
    --kcp-org)
      shift
      KCP_ORG="$1"
      ;;
    --kcp-workspace)
      shift
      KCP_WORKSPACE="$1"
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

  WORK_DIR=${WORK_DIR:-./work}

  KCP_ORG=${KCP_ORG:-$(kubectl kcp workspace current | cut -d\" -f2 | cut -d: -f1,2)}
  KCP_WORKSPACE=${KCP_WORKSPACE:-compute}
}

init() {
  WORK_DIR="${WORK_DIR:-$SCRIPT_DIR/work}"

  credentials_dir="$WORK_DIR/credentials/kubeconfig"
  mkdir -p "$credentials_dir"
}

generate_kcp_credentials() {
  kcp_instance="$(kubectl config view --minify -o json |
    jq ".clusters[0].cluster.server" |
    sed -r -e "s@.*://([^.]*).*@\1@")"
  kcp_org_short="$(echo "${KCP_ORG}" | tr ':' '.' | cut -d. -f2-)"
  kcp_name="${kcp_instance}.${kcp_org_short}.${KCP_WORKSPACE}"
  printf "[KCP: %s]\n" "$kcp_name"
  kubeconfig="$credentials_dir/kcp/$kcp_name.kubeconfig"

  printf -- "- Create workspace:\n"
  kubectl kcp workspace use "$KCP_ORG" | indent 4
  if ! kubectl kcp workspace use "$KCP_WORKSPACE" >/dev/null 2>&1; then
    kubectl kcp workspace create "$KCP_WORKSPACE" --type=universal --enter >/dev/null
  fi
  kubectl kcp workspace current | indent 4

  printf -- "- Create service account:\n"
  kubectl apply -k "$KUSTOMIZATION" | indent 4

  printf -- "- Generate kubeconfig:\n"
  get_context "pipeline-service-manager" "pipelines-as-code" "pipeline-service-manager" "$kubeconfig"
  printf "KUBECONFIG=%s\n" "$kubeconfig" | indent 4
}

patch_workspace_controller() {
  manifests_dir="$WORK_DIR/environment/kcp/workspace-controller"
  printf -- "- Generate patch for the workspace-controller: "
  echo -n "
patches:
  - target:
      kind: APIBinding
      name: settings-configuration.pipeline-service.io
    patch: |-
      - op: replace
        path: /spec/reference/workspace/path
        value: \"$KCP_ORG:$KCP_WORKSPACE\"
  - target:
      kind: Deployment
      name: settings-controller-manager
    patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/args/2
        value: \"--api-export-workspace=$KCP_ORG:$KCP_WORKSPACE\"
" >> "$manifests_dir/overlays/kustomization.yaml"
  printf "OK\n"
}

main() {
  parse_args "$@"
  prechecks
  init
  generate_kcp_credentials
  patch_workspace_controller
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi
