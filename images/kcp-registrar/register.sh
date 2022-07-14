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

    printf "Usage: KCP_ORG="root:pipelines-service" KCP_WORKSPACE="compute" KCP_SYNC_TAG="release-0.5" DATA_DIR="/workspace" ./register.sh\n\n"

    # Parameters
    printf "The following parameters need to be passed to the script:\n"
    printf "KCP_ORG: the organization for which the workload clusters need to be registered, i.e.: root:pipelines-service\n"
    printf "KCP_WORKSPACE: the name of the workspace where the workload clusters get registered (created if it does not exist), i.e: compute\n"
    printf "KCP_SYNC_TAG: the tag of the kcp syncer image to use (preset in the container image at build time and leveraged by the PipelineRun)\n"
    printf "DATA_DIR: the location of the cluster files\n"
    printf "          a single file with extension kubeconfig is expected in the subdirectory: credentials/kubeconfig/kcp\n"
    printf "          kubeconfig files for compute clusters are expected in the subdirectory: credentials/kubeconfig/compute \n\n"
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

    DATA_DIR=${DATA_DIR:-}
    if [[ -z "${DATA_DIR}" ]]; then
        exit_error "DATA_DIR not set\n\n"
    fi
}

# populate kcp_kcfg with the location of the kubeconfig for connecting to kcp
kcp_kubeconfig() {
    kubeconfig_dir="$DATA_DIR/credentials/kubeconfig"
    if files=($(ls "$kubeconfig_dir/kcp/"*.kubeconfig 2>/dev/null)); then
        if [ ${#files[@]} -ne 1 ]; then
            exit_error "A single kubeconfig file is expected at $kubeconfig_dir/kcp\n\n"
        fi
    else
        exit_error "A single kubeconfig file is expected at $kubeconfig_dir/kcp\n\n"
    fi
    tmp_dir=$(mktemp -d)
    cp -rf "$DATA_DIR/credentials" "$tmp_dir"
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
    files=($(ls "$kubeconfig_dir/compute"))
    for kubeconfig in "${files[@]}"; do
        subs=($(KUBECONFIG="$kubeconfig_dir/compute/${kubeconfig}" kubectl config view -o jsonpath='{range .contexts[*]}{.name}{","}{.context.cluster}{"\n"}{end}'))
        for sub in "${subs[@]}"; do
            context=$(echo -n ${sub} | cut -d ',' -f 1)
            cluster=$(echo -n ${sub} | cut -d ',' -f 2 | cut -d ':' -f 1)
            if ! (echo "${clusters[@]}" | grep "${cluster}"); then
                clusters+=(${cluster})
                contexts+=(${context})
                kubeconfigs+=(${kubeconfig})
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
        KUBECONFIG="$kcp_kcfg" kubectl kcp workspace create "${KCP_WORKSPACE}" --enter >/dev/null 2>&1
    fi
    KUBECONFIG="$kcp_kcfg" kubectl kcp workspace current
}

register() {
    printf "Getting the list of registered clusters\n"
    existing_clusters=$(KUBECONFIG=${kcp_kcfg} kubectl get workloadclusters -o name)

    for i in "${!clusters[@]}"; do
        printf "Processing cluster %s\n" "${clusters[$i]}"
        if echo "${existing_clusters}" | grep "${clusters[$i]}"; then
            printf "Cluster already registered\n"
        else
            printf "Registering cluster\n"
            syncer_manifest="/tmp/syncer-${clusters[$i]}.yaml"
            KUBECONFIG=${kcp_kcfg} kubectl kcp workload sync "${clusters[$i]}" \
                --syncer-image ghcr.io/kcp-dev/kcp/syncer:$KCP_SYNC_TAG \
                --resources deployments.apps,services,ingresses.networking.k8s.io,conditions.tekton.dev,pipelines.tekton.dev,pipelineruns.tekton.dev,pipelineresources.tekton.dev,tasks.tekton.dev,runs.tekton.dev,networkpolicies.networking.k8s.io \
                >"$syncer_manifest"
            KUBECONFIG=${DATA_DIR}/credentials/kubeconfig/compute/${kubeconfigs[$i]} kubectl apply --context ${contexts[$i]} -f "$syncer_manifest"
        fi
    done
}

prechecks
kcp_kubeconfig
if [[ "$(KUBECONFIG=${kcp_kcfg} kubectl kcp workspace current | cut -d\" -f2)" == "$KCP_ORG:$KCP_WORKSPACE" ]]; then
    printf "Workspace: %s" "$KCP_ORG:$KCP_WORKSPACE"
else
    printf "Switching to organization %s\n" "${KCP_ORG}"
    switch_org
    printf "Switching to workspace %s\n" "${KCP_WORKSPACE}"
    switch_ws
fi
get_clusters
printf "Registering clusters to kcp\n"
register
