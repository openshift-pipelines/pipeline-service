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

# Parameters
printf "The following optional parameters can be passed to the script:\n"
printf "KCP_DIR: a directory with kcp source code, default to a git clone of kcp in the system temp directory\n"
printf "KCP_BRANCH: the kcp branch to use. Mind that the script will do a git checkout, to a default release if the branch is not specified\n"
printf "KCP_RUNTIME_DIR: the location of the kcp runtime files, default to a temporary directory\n"
printf "PARAMS: the parameters to start kcp with\n\n"

precheck() {
  if ! command -v "$1" &> /dev/null
  then
    printf "%s could not be found\n" "$1"
    exit 1
  fi
}

KCP_DIR="${KCP_DIR:-}"
kcp-binaries() {
  if [[ -z "${KCP_DIR}" ]]; then
    precheck git
    KCP_PARENT_DIR="$(mktemp -d -t kcp.XXXXXXXXX)"
    pushd "${KCP_PARENT_DIR}"
    git clone https://github.com/kcp-dev/kcp.git
    KCP_DIR="${KCP_PARENT_DIR}/kcp"
    pushd kcp
    KCP_BRANCH="${KCP_BRANCH:-release-0.7}"
    git checkout "${KCP_BRANCH}"
    make build
    popd
    popd
  fi
}

kcp-start() {
  printf "Starting KCP server ...\n"
  (cd "${KCP_RUNTIME_DIR}" && exec "${KCP_DIR}/bin/kcp" start "${PARAMS[@]}") &> "${KCP_RUNTIME_DIR}/kcp.log" &
  KCP_PID=$!
  KCP_PIDS+=("${KCP_PID}")
  wait_command "ls ${KUBECONFIG}" 30
  printf "KCP server started: %s\n" $KCP_PID
  touch "${KCP_RUNTIME_DIR}/kcp-started"

  printf "Waiting for KCP to be ready ...\n"
  wait_command "kubectl --kubeconfig=${KUBECONFIG} get --raw /readyz" 30
  printf "KCP ready\n"
}

ingress-ctrler-start() {
  printf "Starting Ingress Controller\n"
  "${KCP_DIR}/bin/ingress-controller" --kubeconfig="${KUBECONFIG}" --context=system:admin --envoy-listener-port=8181 --envoy-xds-port=18000 &> "${KCP_RUNTIME_DIR}/ingress-controller.log" &
  INGRESS_CONTROLLER_PID=$!
  printf "Ingress Controller started: %s\n" "${INGRESS_CONTROLLER_PID}"
  KCP_PIDS+=("${INGRESS_CONTROLLER_PID}")
}

envoy-start() {
  printf "Starting envoy\n"
  bootstrapAddress="host.docker.internal"
  if [[ "${CONTAINER_ENGINE}" != "docker" ]]; then
    bootstrapAddress="host.containers.internal"
  fi
  sed "s/BOOTSTRAP_ADDRESS/$bootstrapAddress/" "${PARENT_PATH}/envoy-bootstrap.yaml" > "${KCP_RUNTIME_DIR}/envoy-bootstrap.yaml"
  ${CONTAINER_ENGINE} create --rm -t --net=kind -p 8181:8181 docker.io/envoyproxy/envoy-dev:d803505d919aff1c4207b353c3b430edfa047010
  ENVOY_CID=$(${CONTAINER_ENGINE} ps -q -n1)
  ${CONTAINER_ENGINE} cp "${KCP_RUNTIME_DIR}/envoy-bootstrap.yaml" "${ENVOY_CID}:/etc/envoy/envoy.yaml"
  ${CONTAINER_ENGINE} start "${ENVOY_CID}"
  ${CONTAINER_ENGINE} logs -f "${ENVOY_CID}" &> "${KCP_RUNTIME_DIR}/envoy.log" &
  echo "Envoy started in container: ${ENVOY_CID}"
  KCP_CIDS+=("${ENVOY_CID}")
}

create-org() {
  printf "Creating organization\n"
  kubectl --kubeconfig="${KUBECONFIG}" config use-context root
  KUBECONFIG="${KUBECONFIG}" "${KCP_DIR}/bin/kubectl-kcp" workspace use root
  KUBECONFIG="${KUBECONFIG}" "${KCP_DIR}/bin/kubectl-kcp" workspace create --type=organization pipeline-service --enter
}

# Execution
PARENT_PATH=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )

kcp-binaries

KCP_RUNTIME_DIR="${KCP_RUNTIME_DIR:-}"
KCP_RUNTIME_DIR="${KCP_RUNTIME_DIR:-$(mktemp -d -t kcp-pipeline-service.XXXXXXXXX)}"
mkdir -p "$KCP_RUNTIME_DIR"
printf "kcp runtime files in: %s\n" "${KCP_RUNTIME_DIR}"

KUBECONFIG="${KCP_RUNTIME_DIR}/.kcp/admin.kubeconfig"

# shellcheck source=local/utils.sh
source "${PARENT_PATH}/../utils.sh"

detect_container_engine

setupTraps
KCP_PIDS=()
KCP_CIDS=()

PARAMS="${PARAMS:-}"
if [[ -z "${PARAMS}" ]]; then
  PARAMS=(
    --token-auth-file "${PARENT_PATH}/kcp-tokens"
    --profiler-address localhost:6060
    -v 2
  )
fi

kcp-start
printf "KUBECONFIG=%s\n" "${KUBECONFIG}"
printf "kubectl kcp plugin (should be copied to kubectl binary location): %s\n" "${KCP_DIR}/bin/kubectl-kcp"
# old ingress PoC is not working anymore, waiting for kcp-glbc to be usable.
# ingress-ctrler-start
# envoy-start
create-org

touch "${KCP_RUNTIME_DIR}/servers-ready"

printf "\n"
printf "Use ctrl-C to stop all components\n"
printf "\n"

wait
