#!/usr/bin/env bash

# Copyright 2022 The Pipelines-service Authors.
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
printf "PARAMS: the parameters to start kcp with\n\n"

precheck() {
  if ! command -v "$1" &> /dev/null
  then
    printf "%s could not be found\n" "$1"
    exit 1
  fi
}

KCP_DIR="${KCP_DIR:-}"
kcp-binaries () {
  if [[ -z "${KCP_DIR}" ]]; then
    precheck git
    KCP_PARENT_DIR="$(mktemp -d -t kcp.XXXXXXXXX)"
    pushd "${KCP_PARENT_DIR}"
    git clone https://github.com/kcp-dev/kcp.git
    KCP_DIR="${KCP_PARENT_DIR}/kcp"
    pushd kcp
    KCP_BRANCH="${KCP_BRANCH:-release-0.4}"
    git checkout "${KCP_BRANCH}"
    make build
    popd
    popd
  fi
}

kcp-start() {
  printf "Starting KCP server ...\n"
  (cd "${TMP_DIR}" && exec "${KCP_DIR}"/bin/kcp start ${PARAMS}) &> "${TMP_DIR}/kcp.log" &
  KCP_PID=$!
  KCP_PIDS="${KCP_PIDS} ${KCP_PID}"
  printf "KCP server started: %s\n" $KCP_PID

  touch "${TMP_DIR}/kcp-started"

  wait_command "ls ${KUBECONFIG}" 30
  printf "Waiting for KCP to be ready ...\n"
  wait_command "kubectl --kubeconfig=${KUBECONFIG} get --raw /readyz" 30
  printf "KCP ready: %s\n" $?
}

ingress-ctrler-start() {
  printf "Starting Ingress Controller\n"
  "${KCP_DIR}"/bin/ingress-controller --kubeconfig="${KUBECONFIG}" --context=system:admin --envoy-listener-port=8181 --envoy-xds-port=18000 &> "${TMP_DIR}"/ingress-controller.log &
  INGRESS_CONTROLLER_PID=$!
  printf "Ingress Controller started: %s\n" "${INGRESS_CONTROLLER_PID}"
  KCP_PIDS="${KCP_PIDS} ${INGRESS_CONTROLLER_PID}"
}

envoy-start() {
  printf "Starting envoy\n"
  bootstrapAddress="host.docker.internal"
  if [[ "${CONTAINER_ENGINE}" != "docker" ]]; then
    bootstrapAddress="host.containers.internal"
  fi
  sed "s/BOOTSTRAP_ADDRESS/$bootstrapAddress/" "${PARENT_PATH}"/envoy-bootstrap.yaml > "${TMP_DIR}"/envoy-bootstrap.yaml
  ${CONTAINER_ENGINE} create --rm -t --net=kind -p 8181:8181 docker.io/envoyproxy/envoy-dev:d803505d919aff1c4207b353c3b430edfa047010
  ENVOY_CID=$(${CONTAINER_ENGINE} ps -q -n1)
  ${CONTAINER_ENGINE} cp "${TMP_DIR}"/envoy-bootstrap.yaml "${ENVOY_CID}":/etc/envoy/envoy.yaml
  ${CONTAINER_ENGINE} start "${ENVOY_CID}"
  ${CONTAINER_ENGINE} logs -f "${ENVOY_CID}" &> "${TMP_DIR}"/envoy.log &
  echo "Envoy started in container: ${ENVOY_CID}"
  KCP_CIDS="${KCP_CIDS}  ${ENVOY_CID}"
}

create-org() {
  printf "Creating organization\n"
  kubectl --kubeconfig="${KUBECONFIG}" config use-context root
  kubectl --kubeconfig="${KUBECONFIG}" create -f "${PARENT_PATH}"/pipelines-service-org.yaml
}

# Execution

kcp-binaries

TMP_DIR="$(mktemp -d -t kcp-pipelines-service.XXXXXXXXX)"
printf "Temporary directory created: %s\n" "${TMP_DIR}"

KUBECONFIG="${TMP_DIR}/.kcp/admin.kubeconfig"
printf "KUBECONFIG=%s\n" "${KUBECONFIG}"

PARENT_PATH=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )

source "${PARENT_PATH}/../.utils"

detect_container_engine

setupTraps
KCP_PIDS=""
KCP_CIDS=""

PARAMS="${PARAMS:-}"
if [[ -z "${PARAMS}" ]]; then
PARAMS="--token-auth-file ${PARENT_PATH}/kcp-tokens \
--discovery-poll-interval 3s \
--profiler-address localhost:6060 \
-v 2"
fi

kcp-start
ingress-ctrler-start
envoy-start
create-org

touch "${TMP_DIR}/servers-ready"

printf "\n"
printf "Use ctrl-C to stop all components\n"
printf "\n"

wait
