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

SCRIPT_DIR="$(
  cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null
  pwd
)"

source "$SCRIPT_DIR/common.sh"

usage() {
  echo "
Usage:
    ${0##*/} [options]

Test the pipeline service on a cluster running on KCP." >&2
  usage_args
}

init() {
  local ns_locator

  # Retrieve the KCP namespace id
  ns_locator="{\"logical-cluster\":\"$(
    kcp_config kubectl kcp workspace current | cut -d\" -f2
  )\",\"namespace\":\"default\"}"
  # Loop is necessary as it takes KCP time to create the namespace
  while ! plnsvc_config kubectl get ns -o yaml | grep -q "$ns_locator"; do
    sleep 2
  done
  KCP_NS_ID="$(plnsvc_config kubectl get ns -l workloads.kcp.dev/cluster=plnsvc -o json \
    | jq -r '.items[].metadata | select(.annotations."kcp.dev/namespace-locator" 
    | contains("default")) | .name'
  )"
}

print_results() {
  echo "  - Waiting for a bit"
  sleep 30

  echo "  - Resources in kcp"
  kcp_config kubectl get pods,taskruns,pipelineruns
  echo

  echo "  - Resources in the plnsvc in namespace $KCP_NS_ID"
  plnsvc_config kubectl get pods -n "$KCP_NS_ID"
}

pipelines() {
  echo "[Pipelines]"

  echo -n "  - Applications synchronized: "
  argocd_local app wait pipelines-controller >/dev/null
  argocd_local app wait pipelines-crds >/dev/null
  echo "OK"

  echo "  - Running a sample TaskRun and PipelineRun"
  BASE_URL="https://raw.githubusercontent.com/tektoncd/pipeline/v0.32.0"
  for manifest in taskruns/custom-env.yaml pipelineruns/using_context_variables.yaml; do
    # change ubuntu image to ubi to avoid dockerhub registry pull limit
    curl --fail --silent "$BASE_URL/examples/v1beta1/$manifest" \
      | sed 's|ubuntu|registry.access.redhat.com/ubi8/ubi-minimal:latest|' \
      | kcp_config kubectl create -f -
  done

  print_results
  echo
}

triggers() {
  echo "[Triggers]"

  echo -n "  - Applications synchronized: "
  argocd_local app wait triggers-controller >/dev/null
  argocd_local app wait triggers-crds >/dev/null
  argocd_local app wait triggers-interceptors >/dev/null
  echo "OK"

  echo "  - Configuring GitHub listener"
  kcp_config kubectl apply -f https://raw.githubusercontent.com/tektoncd/triggers/v0.18.0/examples/v1beta1/github/github-eventlistener-interceptor.yaml
  kcp_config kubectl apply -f https://raw.githubusercontent.com/tektoncd/triggers/v0.18.0/examples/v1beta1/github/secret.yaml
  sleep 20

  # Simulate the behaviour of a webhook. GitHub sends some payload and trigger a TaskRun.
  echo "  - Simulate a webhook"
  timeout 20 kubectl --kubeconfig "$KUBECONFIG_PLNSVC" -n "$KCP_NS_ID" port-forward service/el-github-listener 8089:8080 &
  sleep 10
  curl --fail --silent \
  -H 'X-GitHub-Event: pull_request' \
  -H 'X-Hub-Signature: sha1=ba0cdc263b3492a74b601d240c27efe81c4720cb' \
  -H 'Content-Type: application/json' \
  -d '{"action": "opened", "pull_request":{"head":{"sha": "28911bbb5a3e2ea034daf1f6be0a822d50e31e73"}},"repository":{"clone_url": "https://github.com/tektoncd/triggers.git"}}' \
  http://localhost:8089

  print_results
  echo
}

main() {
  parse_init "$@"

  init
  pipelines
  triggers
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi
