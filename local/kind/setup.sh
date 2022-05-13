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

prechecks () {
    if ! command -v kind &> /dev/null; then
        printf "Kind could not be found\n"
        exit 1
    fi

    if [[ "${ALLOW_ROOTLESS}" == "true" ]]; then
        echo "Rootless mode enabled"
    fi

    if [[ "${CONTAINER_ENGINE}" != "docker" && "${ALLOW_ROOTLESS}" != "true" ]]; then
        KIND_CMD="sudo kind"
    else
        KIND_CMD="kind"
    fi
}

mk_tmpdir () {
    TMP_DIR="$(mktemp -d -t kind-pipelines-service.XXXXXXXXX)"
    printf "Temporary directory created: %s\n" "${TMP_DIR}"
}

parent_path=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )
pushd "$parent_path"

source ../.utils

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

for cluster in "${CLUSTERS[@]}"; do
    clusterExists=""
    if echo "${EXISTING_CLUSTERS}" | grep "$cluster"; then
        clusterExists="1"
        ${KIND_CMD} export kubeconfig --name "$cluster" --kubeconfig "${TMP_DIR}/${cluster}.kubeconfig"
	if [[  ${KIND_CMD} == "sudo kind" ]]; then
                sudo chmod +r "${TMP_DIR}/${cluster}.kubeconfig"
        fi
    fi

    # Only create the cluster if it does not exist
    if [[ -z "${clusterExists}" ]]; then
        echo "Creating kind cluster ${cluster}"
        cp "${cluster}.config" "${TMP_DIR}/${cluster}.config"
        KIND_EXPERIMENTAL_PROVIDER=${KIND_EXPERIMENTAL_PROVIDER:-} ${KIND_CMD} create cluster \
            --config "${TMP_DIR}/${cluster}.config" \
            --kubeconfig "${TMP_DIR}/${cluster}.kubeconfig"

        if [[ ${KIND_CMD} == "sudo kind" ]]; then
            sudo chmod +r "${TMP_DIR}/${cluster}.kubeconfig"
        fi

        printf "Provisioning ingress router in %s\n" "${cluster}"
        kubectl --kubeconfig "${TMP_DIR}/${cluster}.kubeconfig" apply -f ingress-router.yaml
    fi

    if [[ ! -f "${TMP_DIR}/${cluster}.yaml" ]]; then
        clusterKubeconfig=$(${KIND_CMD} get kubeconfig --name "${cluster}")
        echo "${clusterKubeconfig}" | sed -e 's/^/    /' | cat "${cluster}.yaml" - > "${TMP_DIR}/${cluster}.yaml"
        printf "Manifest for registering the cluster in kcp: %s.yaml\n\n" "${TMP_DIR}/${cluster}"
    fi

done

NO_ARGOCD="${NO_ARGOCD:-}"
if [[ $(tr '[:upper:]' '[:lower:]' <<< "$NO_ARGOCD") != "true" ]]; then
    KUBECONFIG="${TMP_DIR}/${CLUSTERS[0]}.kubeconfig" ../argocd/setup.sh
fi

popd
