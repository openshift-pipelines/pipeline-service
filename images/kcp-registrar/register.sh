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

usage() {

    printf "
Usage:
    %s [options]

Deploy Pipeline Service on the clusters as per the configuration in WORKSPACE_DIR.

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
        Example: 'v0.8.2'
        Can be set through \$KCP_SYNC_TAG.

Optional arguments:
    -w, --workspace-dir WORKSPACE_DIR
        Location of the cluster files related to the environment.
        A single file with extension kubeconfig is expected in the subdirectory: credentials/kubeconfig/kcp
        Kubeconfig files for compute clusters are expected in the subdirectory: credentials/kubeconfig/compute
        Default: \$WORKSPACE_DIR or current directory if the environment
        variable is unset.
    -d, --debug
        Activate tracing/debug mode.
    -h, --help
        Display this message.

Example:
    KCP_SYNC_TAG='v0.8.2' %s --kcp-org 'root:my_org' --kcp-workspace 'my_workspace' --workspace_dir /path/to/my_dir
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

register() {
    local sync_target_name
    for i in "${!clusters[@]}"; do
        printf -- "- %s (%s/%s)\n" "${clusters[$i]}" "$((i+1))" "${#clusters[@]}"
        syncer_manifest="/tmp/syncer-${clusters[$i]}.yaml"
        sync_target_name="$(get_sync_target_name "${clusters[$i]}")"
        KUBECONFIG="${kcp_kcfg}" kubectl kcp workload sync "${sync_target_name}" \
            --syncer-image "ghcr.io/kcp-dev/kcp/syncer:$KCP_SYNC_TAG" \
            --resources deployments.apps,services,ingresses.networking.k8s.io,pipelines.tekton.dev,pipelineruns.tekton.dev,tasks.tekton.dev,runs.tekton.dev,networkpolicies.networking.k8s.io \
            --output-file "$syncer_manifest"
        add_ca_cert_to_syncer_manifest "${kcp_kcfg}" "$syncer_manifest"
        KUBECONFIG="${WORKSPACE_DIR}/credentials/kubeconfig/compute/${kubeconfigs[$i]}" kubectl apply \
            --context "${contexts[$i]}" -f "$syncer_manifest"
    done
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
    ca_cert="$(openssl s_client -showcerts -servername "${servername}" -connect "${host}" </dev/null | openssl x509 | base64 -w 0)"

    ca_cert="${ca_cert}" yq -i '(select(.stringData.kubeconfig != null)) .stringData.kubeconfig |= (fromyaml | .clusters[].cluster."certificate-authority-data" = env(ca_cert) | to_yaml)' "${manifest}"
}

configure_synctarget_ws() {
    manifests_source="$WORKSPACE_DIR/environment/kcp"
    if [[ -d "$manifests_source" ]]; then
        printf "Configuring KCP workspace\n"
        KUBECONFIG=${kcp_kcfg} kubectl apply -k "$manifests_source"
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
    register
    configure_synctarget_ws
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
    main "$@"
fi
