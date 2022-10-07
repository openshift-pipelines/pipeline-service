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

    printf "Usage: KCP_ORG=root:pipeline-service KCP_WORKSPACE=gateway DATA_DIR=/workspace ./install.sh\n\n"

    # Parameters
    printf "The following parameters need to be passed to the script:\n"
    printf "KCP_ORG: the organistation for which the workload clusters need to be registered, i.e.: root:pipeline-service\n"
    printf "KCP_WORKSPACE: the name of the workspace where the gateway gets deployed (created if it does not exist), i.e: gateway.\n"
    printf "DATA_DIR: the location of the cluster files\n"
}

prechecks () {
    KCP_ORG="${KCP_ORG:-}"
    if [[ -z "${KCP_ORG}" ]]; then
        printf "KCP_ORG not set\n\n"
        usage
        exit 1
    fi

    KCP_WORKSPACE="${KCP_WORKSPACE:-}"
    if [[ -z "${KCP_WORKSPACE}" ]]; then
        printf "KCP_WORKSPACE not set\n\n"
        usage
        exit 1
    fi
    
    DATA_DIR="${DATA_DIR:-}"
    if [[ -z "${DATA_DIR}" ]]; then
        printf "DATA_DIR not set\n\n"
        usage
	exit 1
    fi
}

# populate kcp_kcfg with the location of the kubeconfig for connecting to kcp
kcp_kubeconfig() {
    mapfile -t files < <(ls "$DATA_DIR/credentials/kubeconfig/kcp/"*.kubeconfig 2>/dev/null)
    if [ ${#files[@]} -ne 1 ]; then
        printf "A single kubeconfig file is expected at %s\n" "$DATA_DIR/credentials/kubeconfig/kcp"
        usage
        exit 1
    fi
    kcp_kcfg="${files[0]}"
}

switch_org() {
    KUBECONFIG=${kcp_kcfg} kubectl kcp workspace use "${KCP_ORG}"
    if ! (KUBECONFIG=${kcp_kcfg} kubectl api-resources >> /dev/null 2>&1); then
        printf "%s is not a valid organization, wrong kubectl context in use or connectivity issue\n" "${KCP_ORG}"
	usage
	exit 1
    fi
}

switch_ws() {
    if (KUBECONFIG=${kcp_kcfg} kubectl get workspaces -o name | grep "${KCP_WORKSPACE}"); then
        printf "use existing workspace\n"
	KUBECONFIG=${kcp_kcfg} kubectl kcp workspace use "${KCP_WORKSPACE}"

    else
       printf "creating workspace %s\n" "${KCP_WORKSPACE}"
       KUBECONFIG=${kcp_kcfg} kubectl kcp workspace create "${KCP_WORKSPACE}" --type=universal --enter
    fi
}

bind_apis() {
    CONFIG_DIR="${DATA_DIR}/environment/kcp/gateway-bindings"
    KUBECONFIG=${kcp_kcfg} kubectl apply -k "${CONFIG_DIR}"
}
    
install_gateway() {
    CONFIG_DIR="${DATA_DIR}/environment/kcp/gateway"
    KUBECONFIG=${kcp_kcfg} kubectl apply -k "${CONFIG_DIR}"
}

main() {
    prechecks
    kcp_kubeconfig
    printf "Switching to organization %s\n" "${KCP_ORG}"
    switch_org
    printf "Switching to workspace %s\n" "${KCP_WORKSPACE}"
    switch_ws
    printf "Bindind APIs\n"
    bind_apis
    # Give time for the API binding to happen
    sleep 1
    printf "Installing gateway\n"
    install_gateway
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi
