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

    printf "Usage: KCP_WORKSPACE=root:pipeline-service DATA_DIR=/workspace ./install.sh\n\n"

    # Parameters
    printf "The following parameters need to be passed to the script:\n"
    printf "KCP_WORKSPACE: the name of the workspace where the gateway gets deployed, i.e: root:pipeline-service.\n"
    printf "DATA_DIR: the location of the cluster files\n"
}

prechecks () {
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


switch_ws() {
  KUBECONFIG=${kcp_kcfg} kubectl kcp workspace use "${KCP_WORKSPACE}"
  if ! (KUBECONFIG=${kcp_kcfg} kubectl api-resources >> /dev/null 2>&1); then
    printf "%s is not a valid workspace, wrong kubectl context in use or connectivity issue\n" "${KCP_WORKSPACE}"
    usage
    exit 1
  fi
}


install_gateway() {
    CONFIG_DIR="${DATA_DIR}/environment/kcp/gateway"
    KUBECONFIG=${kcp_kcfg} kubectl apply -k "${CONFIG_DIR}"
}

main() {
    prechecks
    kcp_kubeconfig
    printf "Switching to workspace %s\n" "${KCP_WORKSPACE}"
    switch_ws
    printf "Installing gateway\n"
    install_gateway
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi
