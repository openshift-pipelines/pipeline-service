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

# shellcheck shell=bash

wait_command() {
  local command="$1"; shift
  local wait_seconds="${1:-40}"; shift # 40 seconds as default timeout

  until [[ $((wait_seconds--)) -eq 0 ]] || eval "$command &> /dev/null" ; do sleep 1; done

  ((++wait_seconds))
}

cleanup() {
    local ret="$?"
    if [[ $ret -eq 0 ]] || [[ $ret -eq 130 ]];then
      printf "\nTerminating...\n"
    else
      printf "\nExit on failure...\n"
    fi
    if [[ "${#KCP_PIDS[@]}" -gt 0 ]]; then
      printf "\nCleaning up processes %s\n" "${KCP_PIDS[*]}"
      kill "${KCP_PIDS[@]}"
    fi
    if [[ "${#KCP_CIDS[@]}" -gt 0 ]]; then
      printf "\nStopping containers %s\n" "${KCP_CIDS[*]}"
      $CONTAINER_ENGINE stop "${KCP_CIDS[@]}"
    fi
}

setupTraps() {
  for sig in INT QUIT HUP TERM; do
    trap "
      cleanup
      trap - $sig EXIT
      kill -s $sig "'"$$"' "$sig"
  done
  trap "cleanup" EXIT
}

detect_container_engine() {
    CONTAINER_ENGINE="${CONTAINER_ENGINE:-}"
    ALLOW_ROOTLESS="${ALLOW_ROOTLESS:-false}"
    if [[ -n "${CONTAINER_ENGINE}" ]]; then
      return
    fi
    CONTAINER_ENGINE="sudo podman"
    if [[ "${ALLOW_ROOTLESS}" == "true" ]]; then
        CONTAINER_ENGINE=podman
    fi
    if ! command -v podman; then
        CONTAINER_ENGINE=docker
        return
    fi
    if [[ "$OSTYPE" == "darwin"* && -z "$(podman ps)" ]]; then
        # Podman machine is not started
        CONTAINER_ENGINE=docker
        return
    fi
    if [[ "$OSTYPE" == "darwin"* && -z "$(podman system connection ls --format=json)" ]]; then
        CONTAINER_ENGINE=docker
        return
    fi
}
