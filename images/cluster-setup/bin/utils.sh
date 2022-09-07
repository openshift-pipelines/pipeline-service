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

exit_error() {
  printf "\n[ERROR] %s\n" "$@" >&2
  printf "Exiting script.\n"
  exit 1
}

check_deployments() {
  local ns="$1"
  shift
  local deployments=("$@")

  for deploy in "${deployments[@]}"; do
    printf "    - %s: " "$deploy"

    #a loop to check if the deployment exists
    if ! timeout 300s bash -c "while ! kubectl get deployment/$deploy -n $ns >/dev/null 2>/dev/null; do printf '.'; sleep 10; done"; then
      printf "%s not found (timeout)\n" "$deploy"
      kubectl get deployment/"$deploy" -n "$ns"
      exit 1
    else
      printf "Exists"
    fi

    #a loop to check if the deployment is Available and Ready
    if kubectl wait --for=condition=Available=true "deployment/$deploy" -n "$ns" --timeout=100s >/dev/null; then
      printf ", Ready\n"
    else
      kubectl -n "$ns" describe "deployment/$deploy"
      kubectl -n "$ns" logs "deployment/$deploy"
      exit 1
    fi
  done
}
