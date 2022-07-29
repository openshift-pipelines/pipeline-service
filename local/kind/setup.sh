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

prechecks () {
    if ! command -v kind &> /dev/null; then
        printf "Kind could not be found\n"
        exit 1
    fi
    if ! command -v kubectl &> /dev/null; then
        printf "kubectl could not be found\n"
        exit 1
    fi
    if ! command -v jq &> /dev/null; then
        printf "jq could not be found\n"
        exit 1
    fi

    if [[ "${ALLOW_ROOTLESS}" == "true" ]]; then
        printf "Rootless mode enabled\n"
    fi

    if [[ "${CONTAINER_ENGINE}" != "docker" && "${ALLOW_ROOTLESS}" != "true" ]]; then
        KIND_CMD="sudo KIND_EXPERIMENTAL_PROVIDER=podman kind"
    else
        if [[ "${CONTAINER_ENGINE}" != "docker" ]]; then
            export KIND_EXPERIMENTAL_PROVIDER=podman
        fi	
    	KIND_CMD="kind"
    fi
    printf "OS: %s\n" "${OSTYPE}"
    printf "Container engine: %s\n" "${CONTAINER_ENGINE}"
    printf "Using kind command: %s\n" "${KIND_CMD}"
}

mk_tmpdir () {
    TMP_DIR="$(mktemp -d -t kind-pipeline-service.XXXXXXXXX)"
    printf "Temporary directory created: %s\n" "${TMP_DIR}"
}

# Generate a kubeconfig using the IP address of the KinD container instead of localhost
# This IP is accessible from localhost and other containers part of the same container network (bridge)
# This can be used for instance to register the cluster to an Argo CD server installed on a KinD cluster
ip_kubeconfig () {
    container=$(${CONTAINER_ENGINE} ps | grep "${cluster}" | cut -d ' ' -f 1)
    containerip=$(${CONTAINER_ENGINE} inspect "${container}" | jq '.[].NetworkSettings.Networks.kind.IPAddress' | sed 's/"//g')
    ${KIND_CMD} get kubeconfig --internal --name "${cluster}" | sed "s/${cluster}-control-plane/${containerip}/g" > "${TMP_DIR}/${cluster}_ip.kubeconfig"
    printf "kubeconfig created for accessing the cluster API of %s from the KinD/container network: %s\n" "${cluster}"  "${TMP_DIR}/${cluster}_ip.kubeconfig"
    if [[ ${KIND_CMD} == "sudo KIND_EXPERIMENTAL_PROVIDER=podman kind" ]]; then
        sudo chmod +r "${TMP_DIR}/${cluster}_ip.kubeconfig"
    fi
}

parent_path=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )
pushd "$parent_path"

source ../utils.sh

detect_container_engine
prechecks

printf "Preparing kind clusters\n"

mk_tmpdir

CLUSTERS=(
    us-east1
    us-west1
)

echo "Checking existing clusters"
EXISTING_CLUSTERS=$(${KIND_CMD} get clusters 2>/dev/null)

NO_ARGOCD="${NO_ARGOCD:-}"

for cluster in "${CLUSTERS[@]}"; do
    clusterExists=""
    if echo "${EXISTING_CLUSTERS}" | grep "$cluster"; then
        clusterExists="1"
        ${KIND_CMD} export kubeconfig --name "$cluster" --kubeconfig "${TMP_DIR}/${cluster}.kubeconfig"
	if [[  ${KIND_CMD} == "sudo KIND_EXPERIMENTAL_PROVIDER=podman kind" ]]; then
                sudo chmod +r "${TMP_DIR}/${cluster}.kubeconfig"
        fi
	ip_kubeconfig
    fi

    # Only create the cluster if it does not exist
    if [[ -z "${clusterExists}" ]]; then
        echo "Creating kind cluster ${cluster}"
        cp "${cluster}.config" "${TMP_DIR}/${cluster}.config"
        ${KIND_CMD} create cluster \
            --config "${TMP_DIR}/${cluster}.config" \
            --kubeconfig "${TMP_DIR}/${cluster}.kubeconfig"

        if [[ ${KIND_CMD} == "sudo KIND_EXPERIMENTAL_PROVIDER=podman kind" ]]; then
            sudo chmod +r "${TMP_DIR}/${cluster}.kubeconfig"
        fi

        ip_kubeconfig

        printf "Provisioning ingress router in %s\n" "${cluster}"
        kubectl --kubeconfig "${TMP_DIR}/${cluster}.kubeconfig" apply -f "ingress-router-${cluster}.yaml"

	if [[ $(tr '[:upper:]' '[:lower:]' <<< "$NO_ARGOCD") != "true" ]]; then
            KUBECONFIG="${TMP_DIR}/${cluster}.kubeconfig" ../argocd/setup.sh
        fi
    fi
done

popd
