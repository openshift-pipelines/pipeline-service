#!/usr/bin/env bash

#quit if exit status of any cmd is a non-zero value
set -euo pipefail

# Uncomment the below line to enable debugging
# set -x

usage() {

    printf "Usage: WORK_DIR=/workspace CASES=pipelines ./test.sh\n\n"

    # Parameters
    printf "WORK_DIR: the location of the gitops files\n"
    printf "CASES: comma separated list of test cases. Test cases must be any of 'pipelines' or 'triggers'. Pipelines test cases are run by default.\n"
}

prechecks() {
    WORK_DIR="${WORK_DIR:-}"
    if [[ -z "${WORK_DIR}" ]]; then
        printf "WORK_DIR not set\n\n"
        usage
        exit 1
    fi
}

get_namespace() {
  # Retrieve the KCP namespace id
  local ns_locator
  ns_locator="\"workspace\":\"$(
    KUBECONFIG="$KUBECONFIG_KCP" kubectl kcp workspace current | cut -d\" -f2
  )\",\"namespace\":\"default\""
  # Loop is necessary as it takes KCP time to create the namespace
  while ! kubectl get ns -o yaml | grep -q "$ns_locator"; do
    sleep 2
  done

  local KCP_NS_NAME
  KCP_NS_NAME="$(kubectl get ns -l internal.workload.kcp.dev/cluster -o json \
    | jq -r '.items[].metadata | select(.annotations."kcp.dev/namespace-locator"
    | contains("\"namespace\":\"default\"")) | .name'
  )"

  if [ -z "$KCP_NS_NAME" ]; then
    echo "[ERROR] Could not retrieve KCP_NS_NAME"
    exit 1
  fi
  echo "$KCP_NS_NAME"
}

kcp_kubeconfig() {
    mapfile -t files < <(find "$WORK_DIR/credentials/kubeconfig/kcp/" -name \*.kubeconfig)
    echo "${files[0]}"
}

compute_kubeconfig() {
    mapfile -t files < <(find "$WORK_DIR/credentials/kubeconfig/compute/" -name \*.kubeconfig)
    echo "${files[0]}"
}

init() {
  KUBECONFIG_KCP="$(kcp_kubeconfig)"
  KUBECONFIG="$(compute_kubeconfig)"
  export KUBECONFIG
  CASES="${CASES:-"pipelines"}"
}

test_pipelines() {
  echo "[test_pipelines]"
  echo "Running a sample PipelineRun which sets and uses env variables (from tektoncd/pipeline/examples)"
  # create pipelinerun
  if ! KUBECONFIG="$KUBECONFIG_KCP" kubectl get namespace default >/dev/null 2>&1; then
    KUBECONFIG="$KUBECONFIG_KCP" kubectl create namespace default
  fi
  if ! KUBECONFIG="$KUBECONFIG_KCP" kubectl get serviceaccount default >/dev/null 2>&1; then
    KUBECONFIG="$KUBECONFIG_KCP" kubectl create serviceaccount default
  fi
  BASE_URL="https://raw.githubusercontent.com/tektoncd/pipeline/v0.32.0"
  manifest="pipelineruns/using_context_variables.yaml"
  # change ubuntu image to ubi to avoid dockerhub registry pull limit
  curl --fail --silent "$BASE_URL/examples/v1beta1/$manifest" | sed 's|ubuntu|registry.access.redhat.com/ubi8/ubi-minimal:latest|' | sed '/serviceAccountName/d' | KUBECONFIG="$KUBECONFIG_KCP" kubectl create -f -
  
  KUBECONFIG="$KUBECONFIG_KCP" kubectl wait --for=condition=Succeeded  PipelineRun --all --timeout=60s >/dev/null
  echo "Print pipelines custom resources inside kcp"
  KUBECONFIG="$KUBECONFIG_KCP" kubectl get pipelineruns
  echo "Print kube resources in the physical cluster (Note: physical cluster will not know what pipelinesruns are)"
  
  KCP_NS_NAME="$(get_namespace)"
  kubectl get pods -n "$KCP_NS_NAME"
}

test_triggers() {
  echo "Simulating a Github PR through a curl request which creates a TaskRun (from tektoncd/triggers/examples)"
  KUBECONFIG=$KUBECONFIG_KCP kubectl apply -f https://raw.githubusercontent.com/tektoncd/triggers/v0.18.0/examples/v1beta1/github/github-eventlistener-interceptor.yaml
  KUBECONFIG=$KUBECONFIG_KCP kubectl apply -f https://raw.githubusercontent.com/tektoncd/triggers/v0.18.0/examples/v1beta1/github/secret.yaml
  sleep 20
  # Simulate the behaviour of a webhook. GitHub sends some payload and trigger a TaskRun.
  kubectl -n "$(get_namespace)" port-forward service/el-github-listener 8089:8080 &
  SVC_FORWARD_PID=$!
  sleep 10
  curl -v \
  -H 'X-GitHub-Event: pull_request' \
  -H 'X-Hub-Signature: sha1=ba0cdc263b3492a74b601d240c27efe81c4720cb' \
  -H 'Content-Type: application/json' \
  -d '{"action": "opened", "pull_request":{"head":{"sha": "28911bbb5a3e2ea034daf1f6be0a822d50e31e73"}},"repository":{"clone_url": "https://github.com/tektoncd/triggers.git"}}' \
  http://localhost:8089
  kill $SVC_FORWARD_PID
  sleep 20
  KUBECONFIG="$KUBECONFIG_KCP" kubectl get pipelineruns
}

main() {
  prechecks
  init
  IFS="," read -r -a cases <<< "$CASES"
  for case in "${cases[@]}"
  do
    case $case in
    pipelines|triggers)
      test_"$case"
      ;;
    *)
      echo "Incorrect case name '[$case]'"
      usage
      exit 1
      ;;
    esac
  done
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi
