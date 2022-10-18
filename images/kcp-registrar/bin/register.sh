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

usage() {

    printf "
Usage:
    %s [options]

Register compute clusters as per the environment configured in WORKSPACE_DIR.

Mandatory arguments:
    --kcp-org KCP_ORG
        Organization for which the workload clusters need to be registered.
        Example: 'root:pipeline-service'.
        Can be set through \$KCP_ORG.
    --kcp-workspace KCP_WORKSPACE
        Name of the workspace where the workload clusters get registered (created if it
        does not exist).
        Example: 'compute'.
        Can be set through \$KCP_WORKSPACE.
    --kcp-sync-tag KCP_SYNC_TAG
        Tag of the kcp syncer image to use (preset in the container image at build time
        and leveraged by the PipelineRun).
        Example: 'v0.9.0'
        Can be set through \$KCP_SYNC_TAG.

Optional arguments:
    -w, --workspace-dir WORKSPACE_DIR
        Location of the cluster files related to the environment.
        A single file with extension kubeconfig is expected in the subdirectory: credentials/kubeconfig/kcp
        Kubeconfig files for compute clusters are expected in the subdirectory: credentials/kubeconfig/compute
        Default: \$WORKSPACE_DIR or current directory if the environment
        variable is unset.
    -s, --crs-to-sync
        A comma separated list of Custom Resources to sync with kcp.
        Default: deployments.apps,services,ingresses.networking.k8s.io,networkpolicies.networking.k8s.io,pipelines.tekton.dev,pipelineruns.tekton.dev,tasks.tekton.dev,repositories.pipelinesascode.tekton.dev
    -d, --debug
        Activate tracing/debug mode.
    -h, --help
        Display this message.

Example:
    KCP_SYNC_TAG='v0.9.0' %s --kcp-org 'root:my_org' --kcp-workspace 'my_workspace' --workspace_dir /path/to/my_dir
" "${0##*/}" "${0##*/}" >&2
}

parse_args() {
    WORKSPACE_DIR="${WORKSPACE_DIR:-$PWD}"

    while [[ $# -gt 0 ]]; do
        case $1 in
        --kcp-org)
            shift
            KCP_ORG="$1"
            ;;
        --kcp-workspace)
            shift
            KCP_WORKSPACE="$1"
            ;;
        --kcp-sync-tag)
            shift
            KCP_SYNC_TAG="$1"
            ;;
        -w | --workspace-dir)
            shift
            WORKSPACE_DIR="$1"
            ;;
        -s | --crs-to-sync)
            shift
            CRS_TO_SYNC="$1"
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
    printf "[ERROR] %s" "$@" >&2
    usage
    exit 1
}

function indent () {
        sed "s/^/$(printf "%$1s")/"
}

prechecks() {
    KCP_ORG=${KCP_ORG:-}
    if [[ -z "${KCP_ORG}" ]]; then
        exit_error "KCP_ORG not set\n\n"
    fi

    KCP_WORKSPACE=${KCP_WORKSPACE:-}
    if [[ -z "${KCP_WORKSPACE}" ]]; then
        exit_error "KCP_WORKSPACE not set\n\n"
    fi

    KCP_SYNC_TAG=${KCP_SYNC_TAG:-}
    if [[ -z "${KCP_SYNC_TAG}" ]]; then
        exit_error "KCP_SYNC_TAG not set\n\n"
    fi

    WORKSPACE_DIR=${WORKSPACE_DIR:-}
    if [[ -z "${WORKSPACE_DIR}" ]]; then
        exit_error "WORKSPACE_DIR not set\n\n"
    fi

    CRS_TO_SYNC="${CRS_TO_SYNC:-deployments.apps,services,ingresses.networking.k8s.io,networkpolicies.networking.k8s.io,pipelines.tekton.dev,pipelineruns.tekton.dev,tasks.tekton.dev,repositories.pipelinesascode.tekton.dev}"

    WORKSPACE_DIR="$(cd "$WORKSPACE_DIR" >/dev/null && pwd)" || exit_error "WORKSPACE_DIR '$WORKSPACE_DIR' cannot be accessed\n\n"
}

# populate kcp_kcfg with the location of the kubeconfig for connecting to kcp
kcp_kubeconfig() {
    kubeconfig_dir="$WORKSPACE_DIR/credentials/kubeconfig"
    mapfile -t files < <(ls "$kubeconfig_dir/kcp/"*.kubeconfig 2>/dev/null)
    if [ ${#files[@]} -ne 1 ]; then
        exit_error "A single kubeconfig file is expected at $kubeconfig_dir/kcp\n\n"
    fi
    tmp_dir=$(mktemp -d)
    cp -rf "$WORKSPACE_DIR/credentials" "$tmp_dir"
    kubeconfig_dir="$tmp_dir/credentials/kubeconfig"
    kcp_kcfg="$(ls "$kubeconfig_dir/kcp/"*.kubeconfig)"
}

# populate clusters with the cluster names taken from the kubconfig
# populate contexts with the context name taken from the kubeconfig
# populate kubconfigs with the associated kubeconfig for each cluster name
# only consider the first context for a specific cluster
get_clusters() {
    clusters=()
    contexts=()
    kubeconfigs=()
    mapfile -t files < <(ls "$kubeconfig_dir/compute")
    for kubeconfig in "${files[@]}"; do
        mapfile -t subs < <(KUBECONFIG="$kubeconfig_dir/compute/${kubeconfig}" kubectl config view -o jsonpath='{range .contexts[*]}{.name}{","}{.context.cluster}{"\n"}{end}')
        for sub in "${subs[@]}"; do
            context=$(echo -n "${sub}" | cut -d ',' -f 1)
            cluster=$(echo -n "${sub}" | cut -d ',' -f 2 | cut -d ':' -f 1)
            if ! (echo "${clusters[@]}" | grep -q "${cluster}") \
                && (find "$WORKSPACE_DIR/environment/compute" -type d -name "${cluster}" | grep -q "${cluster}" >/dev/null); then
                clusters+=("${cluster}")
                contexts+=("${context}")
                kubeconfigs+=("${kubeconfig}")
            fi
        done
    done
}

switch_org() {
    KUBECONFIG="$kcp_kcfg" kubectl kcp workspace use "${KCP_ORG}"
    if ! (KUBECONFIG="$kcp_kcfg" kubectl api-resources >>/dev/null 2>&1); then
        KUBECONFIG="$kcp_kcfg" kubectl api-resources
        exit_error "${KCP_ORG} is not a valid organization, wrong kubectl context in use or connectivity issue\n\n"
    fi
}

switch_ws() {
    if KUBECONFIG="$kcp_kcfg" kubectl kcp workspace use "${KCP_WORKSPACE}" >/dev/null 2>&1; then
        printf "  - Use existing workspace\n"
    else
        printf "  - Create workspace %s\n" "${KCP_WORKSPACE}"
        KUBECONFIG="$kcp_kcfg" kubectl kcp workspace create "${KCP_WORKSPACE}" --type=universal --enter >/dev/null 2>&1
    fi
    KUBECONFIG="$kcp_kcfg" kubectl kcp workspace current
}

get_sync_target_name() {
    local cluster_name="$1"

    if [[ -z ${cluster_name} ]]; then
        exit_error "Can't return SyncTarget Name because of missing cluster name!\n\n"
    fi

    local len=${#cluster_name}
    if [ "$len" -le 43 ]; then
        echo "$cluster_name"
    else
        echo -n "$cluster_name" | md5sum | cut -d ' ' -f1
    fi
}

register_cluster() {
      local sync_target_name
        syncer_manifest="/tmp/syncer-${clusters[$i]}.yaml"
        sync_target_name="$(get_sync_target_name "${clusters[$i]}")"
        KUBECONFIG="${kcp_kcfg}" kubectl kcp workload sync "${sync_target_name}" \
            --syncer-image "ghcr.io/kcp-dev/kcp/syncer:$KCP_SYNC_TAG" \
            --resources "$CRS_TO_SYNC"\
            --output-file "$syncer_manifest"
        # Set a restricted security context
        patch="$(dirname "$SCRIPT_DIR")/data/syncer-patch.yaml" yq -i \
          'select(.kind == "Deployment").spec.template.spec.containers[0].securityContext |= load(strenv(patch))' \
          "$syncer_manifest"
        add_ca_cert_to_syncer_manifest "${kcp_kcfg}" "$syncer_manifest"
        # Add annotations required by kcp-glbc
        # Commenting the below line, which adds an annotation, as this is causing issues with the syncer being unable to sync the status from synctarget back to the kcp workspace.
        # Issue being tracked here - https://github.com/kcp-dev/kcp/issues/2147
#        KUBECONFIG="${kcp_kcfg}" kubectl annotate --overwrite synctarget "${sync_target_name}" featuregates.experimental.workload.kcp.dev/advancedscheduling='true'
        KUBECONFIG="${kcp_kcfg}" kubectl label --overwrite synctarget "${sync_target_name}" kuadrant.dev/synctarget="${sync_target_name}"

        KUBECONFIG="${WORKSPACE_DIR}/credentials/kubeconfig/compute/${kubeconfigs[$i]}" kubectl apply \
            --context "${contexts[$i]}" -f "$syncer_manifest"
}

add_ca_cert_to_syncer_manifest() {
    config=$1
    manifest=$2
    # Display a minified version of the kubeconfig that only includes the current context. Pick
    # the first server from the list (there should only ever be one due to --minify). Extract
    # the host name from the server URL.
    host="$(KUBECONFIG="${config}" kubectl config view --minify | yq '.clusters[0].cluster.server' | cut -d/ -f3)"
    # hostname may include port number, remove it if it's there
    servername="$(echo "$host" | cut -d: -f1)"
    # https://stackoverflow.com/a/46464081
    base64_wrap_flag_name="--wrap"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        base64_wrap_flag_name="--break"
    fi
    ca_cert="$(openssl s_client -showcerts -servername "${servername}" -connect "${host}" </dev/null 2>/dev/null | openssl x509 | base64 $base64_wrap_flag_name 0)"
    ca_cert="${ca_cert}" yq -i '(select(.stringData.kubeconfig != null)) .stringData.kubeconfig |= (fromyaml | .clusters[].cluster."certificate-authority-data" = env(ca_cert) | to_yaml)' "${manifest}"
}

configure_synctarget_ws() {
    manifests_source="$WORKSPACE_DIR/environment/kcp"
    if [[ -d "$manifests_source" ]]; then
        printf "Configuring KCP workspace\n"
        KUBECONFIG=${kcp_kcfg} kubectl apply -k "$manifests_source" | indent 2
    fi
}

check_cr_sync() {
  # Wait until CRDs are synced to KCP
  echo -n "- Sync CRDs to KCP: "
  local cr_regexp
  cr_regexp="$(
    IFS=\|
    echo "${CRS_TO_SYNC[*]}"
  )"
  cr_regexp=$(echo "$cr_regexp" | tr "," \|)
  readarray -td, crs_to_sync_arr <<<"$CRS_TO_SYNC"; declare -p crs_to_sync_arr >/dev/null;

  local wait_period=0
  while [[ "$(KUBECONFIG=${kcp_kcfg} kubectl api-resources -o name 2>&1 | grep -Ewc "$cr_regexp")" -ne ${#crs_to_sync_arr[@]} ]]; do
    wait_period=$((wait_period + 10))
    #when wait_period is reached, print out the CR resources that is not synced to KCP
    if [ "$wait_period" -gt 300 ]; then
      echo "Failed to sync following resources to KCP: "
      cr_synced=$(KUBECONFIG="$KUBECONFIG_KCP" kubectl api-resources -o name)
      for cr in "${CRS_TO_SYNC[@]}"; do
        if [ "$(echo "$cr_synced" | grep -wc "$cr")" -eq 0 ]; then
          echo "    * $cr"
        fi
      done
      exit 1
    fi
    echo -n "."
    sleep 10
  done
  echo "OK"
}

install_workspace_controller() {
  ws_controller_manifests="$WORKSPACE_DIR/environment/kcp/workspace-controller/overlays"
  if [[ -d "$ws_controller_manifests" ]]; then
    printf "Deploying Workspace Controller into the workspace\n"
    KUBECONFIG=${kcp_kcfg} kubectl apply -k "$ws_controller_manifests" | indent 2
  fi
}

main() {
    parse_args "$@"
    prechecks
    kcp_kubeconfig
    if [[ "$(KUBECONFIG=${kcp_kcfg} kubectl kcp workspace current | cut -d\" -f2)" == "$KCP_ORG:$KCP_WORKSPACE" ]]; then
        printf "Workspace: %s\n" "$KCP_ORG:$KCP_WORKSPACE"
    else
        printf "Switching to organization %s\n" "${KCP_ORG}"
        switch_org
        printf "Switching to workspace %s\n" "${KCP_WORKSPACE}"
        switch_ws
    fi
    get_clusters
    printf "Registering clusters to kcp\n"
    for i in "${!clusters[@]}"; do
        printf -- "- %s (%s/%s)\n" "${clusters[$i]}" "$((i+1))" "${#clusters[@]}"
        register_cluster 2>&1 | indent 2
    done
    configure_synctarget_ws
    check_cr_sync
    install_workspace_controller
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
    main "$@"
fi
