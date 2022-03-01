#!/usr/bin/env bash

#quit if exit status of any cmd is a non-zero value
set -exuo pipefail

KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
export KUBECONFIG=$KUBECONFIG

#install pipelines/triggers based on args
if [ $# -eq 0 ]; then
  echo "No args passed; exiting now! ckcp is running in a pod"
else
  for arg in "$@"
  do
    if [ $arg == "pipelines" ]; then
      echo "Arg $arg passed. Running pipelines tests..."
      echo "Running a sample TaskRun and PipelineRun which sets and uses env variables (from tektoncd/pipeline/examples)"

      #create taskrun and pipelinerun
      KUBECONFIG=kubeconfig/admin.kubeconfig kubectl create serviceaccount default
      KUBECONFIG=kubeconfig/admin.kubeconfig kubectl create -f pipeline/examples/v1beta1/taskruns/custom-env.yaml
      KUBECONFIG=kubeconfig/admin.kubeconfig kubectl create -f pipeline/examples/v1beta1/pipelineruns/using_context_variables.yaml
      sleep 20

      echo "Print pipelines custom resources inside kcp"
      KUBECONFIG=kubeconfig/admin.kubeconfig kubectl get pods,taskruns,pipelineruns
      echo "Print kube resources in the physical cluster (Note: physical cluster will not know what taskruns or pipelinesruns are)"
      KUBECONFIG=$KUBECONFIG kubectl get pods -n kcpe2cca7df639571aaea31e2a733771938dc381f7762ff7a077100ffad

    elif [ $arg == "triggers" ]; then
      echo "Arg triggers passed. Running triggers tests..."
      echo "Simulating a Github PR through a curl request which creates a TaskRun (from tektoncd/triggers/examples)"

      # Simulate the behaviour of a webhook. GitHub sends some payload and trigger a TaskRun.
      KUBECONFIG=$KUBECONFIG kubectl -n kcpe2cca7df639571aaea31e2a733771938dc381f7762ff7a077100ffad port-forward service/el-github-listener 8089:8080 &
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
      KUBECONFIG=kubeconfig/admin.kubeconfig kubectl get taskruns,pipelineruns
    else
      echo "Incorrect argument/s passed. Allowed args are 'pipelines' or 'triggers' or 'pipelines triggers'"
    fi
  done
fi

