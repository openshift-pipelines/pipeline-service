#!/usr/bin/env bash

#quit if exit status of any cmd is a non-zero value
set -exuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" >/dev/null ; pwd)"
KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
export KUBECONFIG=$KUBECONFIG
KUBECONFIG_KCP="${KUBECONFIG_KCP:-$SCRIPT_DIR/work/kubeconfig/admin.kubeconfig}"

get_namespace() {
  # Retrieve the KCP namespace id
  local ns_locator="{\"logical-cluster\":\"$(
    KUBECONFIG="$KUBECONFIG_KCP" kubectl kcp workspace current | cut -d\" -f2
  )\",\"namespace\":\"default\"}"
  # Loop is necessary as it takes KCP time to create the namespace
  while ! kubectl get ns -o yaml | grep -q "$ns_locator"; do
    sleep 2
  done
  local KCP_NS_NAME="$(kubectl get ns -l internal.workload.kcp.dev/cluster=local -o json \
    | jq -r '.items[].metadata | select(.annotations."kcp.dev/namespace-locator" 
    | contains("\"namespace\":\"default\"")) | .name'
  )"
  echo $KCP_NS_NAME
}


#install pipelines/triggers based on args
if [ $# -eq 0 ]; then
  echo "No args passed; exiting now! ckcp is running in a pod"
else
  for arg in "$@"
  do
    if [ $arg == "pipelines" ]; then
      echo "Arg $arg passed. Running pipelines tests..."
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
      
      sleep 20

      echo "Print pipelines custom resources inside kcp"
      # KUBECONFIG="$KUBECONFIG_KCP" kubectl get pods,pipelineruns
      KUBECONFIG="$KUBECONFIG_KCP" kubectl get pipelineruns
      echo "Print kube resources in the physical cluster (Note: physical cluster will not know what pipelinesruns are)"
      
      KCP_NS_NAME="$(get_namespace)"
      kubectl get pods -n $KCP_NS_NAME

    elif [ $arg == "triggers" ]; then
      echo "Arg triggers passed. Running triggers tests..."

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
    else
      echo "Incorrect argument/s passed. Allowed args are 'pipelines' or 'triggers' or 'pipelines triggers'"
    fi
  done
fi

