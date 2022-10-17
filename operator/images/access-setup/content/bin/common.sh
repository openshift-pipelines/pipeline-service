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
    printf "[ERROR] %s\n" "$@" >&2
    usage
    exit 1
}

get_context() {
  # Helper function to generate a kubeconfig file for a service account
  local sa_context="$1"
  local namespace="$2"
  local sa="$3"
  local target="$4"
  local current_context

  mkdir -p "$(dirname "$target")"
  cp "$KUBECONFIG" "$target"

  current_context="$(KUBECONFIG="$target" kubectl config current-context)"

  if ! command -v jq &>/dev/null 2>&1; then
    printf "[ERROR] Install jq\n" >&2
    exit 1
  fi

  for _ in {1..5}
  do
    mapfile -t sa_tokens < <(KUBECONFIG="$target"  kubectl -n "$namespace" get secrets -o json|
               jq -r --arg SA "$sa" '.items[] | select(.type=="kubernetes.io/service-account-token" and .metadata.annotations["kubernetes.io/service-account.name"]==$SA)| .metadata.name')
    if [ ${#sa_tokens[@]} -ne 0 ]; then
      break
    fi
    sleep 5
  done
  if [ ${#sa_tokens[@]} -eq 0 ]; then
      printf "Failed to get service account token\n"
      exit 1
  fi
  sa_token_data=$(KUBECONFIG="$target" kubectl get secret "${sa_tokens[0]}" -n "$namespace" -o jsonpath="{.data.token}"|base64 -d)

  current_cluster="$(KUBECONFIG="$target" kubectl config view \
    -o jsonpath="{.contexts[?(@.name==\"$current_context\")].context.cluster}")"

  KUBECONFIG="$target" kubectl config set-credentials "$sa" --token="$sa_token_data" &>/dev/null
  KUBECONFIG="$target" kubectl config set-context "$sa_context" --user="$sa" --cluster="$current_cluster" &>/dev/null
  KUBECONFIG="$target" kubectl config use-context "$sa_context" &>/dev/null
  KUBECONFIG="$target" kubectl config view --flatten --minify >"$target.new"
  mv "$target.new" "$target"
}

function indent () {
        sed "s/^/$(printf "%$1s")/"
}
