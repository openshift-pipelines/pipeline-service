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

    printf "Usage: KCP_ORG="root:pipelines-service" KCP_WORKSPACE="compute" DATA_DIR="/workspace" ./register.sh\n\n"

    # Parameters
    printf "The following parameters need to be passed to the script:\n"
    printf "KCP_ORG: the organistation for which the workload clusters need to be registered, i.e.: root:pipelines-service\n"
    printf "KCP_WORKSPACE: the name of the workspace where the workload clusters get registered (created if it does not exist), i.e: compute\n"
    printf "DATA_DIR: the location of the cluster files\n"
    printf "          a single file with extension kubeconfig is expected in the subdirectory: credentials/kubeconfig/kcp\n"
    printf "          kubeconfig files for compute clusters are expected in the subdirectory: credentials/kubeconfig/compute \n\n"
}

prechecks () {
    KCP_ORG=${KCP_ORG:-}
    if [[ -z "${KCP_ORG}" ]]; then
        printf "KCP_ORG not set\n\n"
        usage
        exit 1
    fi

    KCP_ORG=${KCP_WORKSPACE:-}
    if [[ -z "${KCP_WORKSPACE}" ]]; then
        printf "KCP_WORKSPACE not set\n\n"
        usage
        exit 1
    fi
    
    DATA_DIR=${DATA_DIR:-}
    if [[ -z "${DATA_DIR}" ]]; then
        printf "DATA_DIR not set\n\n"
        usage
	exit 1
    fi
}

# populate kcp_kcfg with the location of the kubeconfig for connecting to kcp
kcp_kubeconfig() {
    if files=($(ls $DATA_DIR/credentials/kubeconfig/kcp/*.kubeconfig 2>/dev/null)); then
        if [ ${#files[@]} -ne 1 ]; then
            printf "A single kubeconfig file is expected at %s\n" "$DATA_DIR/credentials/kubeconfig/kcp"
            usage
            exit 1
        fi
        kcp_kcfg="${files[0]}"
    else
        printf "A single kubeconfig file is expected at %s\n" "$DATA_DIR/credentials/kubeconfig/kcp"
        usage
        exit 1
    fi
}

# populate clusters with the cluster names taken from the kubconfig
# populate contexts with the context name taken from the kubeconfig
# populate kubconfigs with the associated kubeconfig for each cluster name
# only consider the first context for a specific cluster
get_clusters() {
    clusters=()
    contexts=()
    kubeconfigs=()
    files=($(ls $DATA_DIR/credentials/kubeconfig/compute))
    for kubeconfig in "${files[@]}"; do
        subs=($(KUBECONFIG=${DATA_DIR}/credentials/kubeconfig/compute/${kubeconfig} kubectl config view -o jsonpath='{range .contexts[*]}{.name}{","}{.context.cluster}{"\n"}{end}'))
        for sub in "${subs[@]}"; do
            context=$(echo -n ${sub} | cut -d ',' -f 1)
	    cluster=$(echo -n ${sub} | cut -d ',' -f 2 | cut -d ':' -f 1)
	    if ! (echo "${clusters[@]}" | grep "${cluster}"); then
                clusters+=( ${cluster} )
                contexts+=( ${context} )
                kubeconfigs+=( ${kubeconfig} )
            fi
        done
    done
}

switch_org() {
    KUBECONFIG=${kcp_kcfg} kubectl kcp workspace use ${KCP_ORG}
    if ! (KUBECONFIG=${kcp_kcfg} kubectl api-resources >> /dev/null 2>&1); then
        printf "%s is not a valid organization, wrong kubectl context in use or connectivity issue\n" ${KCP_ORG}
	usage
	exit 1
    fi
}

switch_ws() {
    if (KUBECONFIG=${kcp_kcfg} kubectl get workspaces -o name | grep "${KCP_WORKSPACE}"); then
        printf "use existing workspace\n"
	KUBECONFIG=${kcp_kcfg} kubectl kcp workspace use ${KCP_WORKSPACE}

    else
       printf "creating workspace %s\n" "${KCP_WORKSPACE}"
       KUBECONFIG=${kcp_kcfg} kubectl kcp workspace create "${KCP_WORKSPACE}" --enter
    fi
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
            KUBECONFIG=${kcp_kcfg} kubectl kcp workload sync "${clusters[$i]}" \
                 --syncer-image ghcr.io/kcp-dev/kcp/syncer:$KCP_TAG \
		 --resources deployments.apps,services,ingresses.networking.k8s.io,conditions.tekton.dev,pipelines.tekton.dev,pipelineruns.tekton.dev,pipelineresources.tekton.dev,runs.tekton.dev,tasks.tekton.dev,taskruns.tekton.dev > /tmp/syncer-${clusters[$i]}.yaml
            KUBECONFIG=${DATA_DIR}/credentials/kubeconfig/compute/${kubeconfigs[$i]} kubectl apply --context ${contexts[$i]} -f /tmp/syncer-${clusters[$i]}.yaml 
        fi
    done
}

kcp_kubeconfig
printf "Switching to organization %s\n" ${KCP_ORG}
switch_org
printf "Switching to workspace %s\n" ${KCP_WORKSPACE}
switch_ws
get_clusters
printf "Registering clusters to kcp\n"
register

