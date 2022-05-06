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

    printf "Usage: ARGO_URL="https://argoserver.com" ARGO_USER="user" ARGO_PWD="xxxxxxxxx" DATA_DIR="/workspace" ./register.sh\n\n"

    # Parameters
    printf "The following parameters need to be passed to the script:\n"
    printf "ARGO_URL: the address of the Argo CD server the clusters need to be registered to\n"
    printf "ARGO_USER: the user for the authentication\n"
    printf "ARGO_PWD: the password for the authentication\n"
    printf "DATA_DIR: the location of the cluster files\n"
    printf "INSECURE (optional): whether insecured connection to Argo CD should be allowed. Default value: false\n\n"
}

prechecks () {
    if ! command -v argocd &> /dev/null; then
        printf "Argocd CLI could not be found\n"
    	exit 1
    fi
    ARGO_URL=${ARGO_URL:-}
    if [[ -z "${ARGO_URL}" ]]; then
        printf "ARGO_URL not set\n\n"
        usage
        exit 1	
    fi
    ARGO_USER=${ARGO_USER:-}
    if [[ -z "${ARGO_USER}" ]]; then
        printf "ARGO_USER not set\n\n"
        usage
	exit 1
    fi
    ARGO_PWD=${ARGO_PWD:-}
    if [[ -z "${ARGO_PWD}" ]]; then
	printf "ARGO_PWD not set\n\n"
        usage
	exit 1
    fi
    DATA_DIR=${DATA_DIR:-}
    if [[ -z "${DATA_DIR}" ]]; then
        printf "DATA_DIR not set\n\n"
        usage
	exit 1
    fi
    INSECURE=${INSECURE:-}
    if [[ $(tr '[:upper:]' '[:lower:]' <<< "$INSECURE") == "true" ]]; then
	printf "insecured connection to Argo CD allowed!\n"
        insecure="--insecure"
    else
        insecure=""
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
    files=($(ls $DATA_DIR/gitops/credentials/kubeconfig/compute))
    for kubeconfig in "${files[@]}"; do
        subs=($(KUBECONFIG=${DATA_DIR}/gitops/credentials/kubeconfig/compute/${kubeconfig} kubectl config view -o jsonpath='{range .contexts[*]}{.name}{","}{.context.cluster}{"\n"}{end}'))
        for sub in "${subs[@]}"; do
            context=$(echo -n ${sub} | cut -d ',' -f 1)
            cluster=$(echo -n ${sub} | cut -d ',' -f 2)
	    if ! (echo "${clusters[@]}" | grep "${cluster}"); then
                clusters+=( ${cluster} )
                contexts+=( ${context} )
                kubeconfigs+=( ${kubeconfig} )
            fi
        done
    done
}

registration() {
    printf "Logging into Argo CD\n"
    # TODO: there may be a better way than user/password
    # there should be no assumption that Argo CD runs on the same cluster
    argocd ${insecure} login $ARGO_URL --username $ARGO_USER --password $ARGO_PWD

    printf "Getting the list of registered clusters\n"
    existing_clusters=$(argocd cluster list -o json | jq '.[].name')

    for i in "${!clusters[@]}"; do
        printf "Processing cluster %s\n" "${clusters[$i]}"
        if echo "${existing_clusters}" | grep "${clusters[$i]}"; then
            printf "Cluster already registered\n"
        else
            printf "Registering cluster\n"
            # Split between namespace creation and application of rbac policies:
            # - `argocd cluster add` requires the namespaces to exist
            # - `argocd cluster add` applies default rbac that may differ from what is desired
            KUBECONFIG=${DATA_DIR}/gitops/credentials/kubeconfig/compute/${kubeconfigs[$i]} kubectl apply -k ${DATA_DIR}/gitops/environment/compute/${clusters[$i]}/namespaces
            KUBECONFIG=${DATA_DIR}/gitops/credentials/kubeconfig/compute/${kubeconfigs[$i]} argocd -y ${insecure} cluster add "${contexts[$i]}" --system-namespace argocd-management --namespace=tekton-pipelines --namespace=kcp-syncer
            KUBECONFIG=${DATA_DIR}/gitops/credentials/kubeconfig/compute/${kubeconfigs[$i]} kubectl apply -k ${DATA_DIR}/gitops/environment/compute/${clusters[$i]}/argocd-rbac
        fi
    done
}

parent_path=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )

prechecks

printf "Retrieving clusters\n"
get_clusters

printf "Registering clusters and provisioning credentials for Argo CD\n"
registration

