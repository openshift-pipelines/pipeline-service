#!/usr/bin/env bash

#quit if exit status of any cmd is a non-zero value
set -euo pipefail

# Uncomment the below line to enable debugging
# set -x

usage() {

    printf "Usage: WORK_DIR=/workspace CASES=pipelines ./test.sh\n\n"

    # Parameters
    printf "WORK_DIR: the location of the gitops files\n"
    printf "CASES: comma separated list of test cases. Test cases must be any of 'chains', 'pipelines' or 'triggers'. 'chains' and 'pipelines' are run by default.\n"
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
    # It needs admin user to list Pod resources in compute cluster
    mapfile -t files < <(find "$WORK_DIR/credentials/kubeconfig/compute/" -name \*.kubeconfig.base)
    echo "${files[0]}"
}

init() {
  SCRIPT_DIR=$(
    cd "$(dirname "$0")" >/dev/null
    pwd
  )
  KUBECONFIG_KCP="$(kcp_kubeconfig)"
  KUBECONFIG="$(compute_kubeconfig)"
  export KUBECONFIG
  CASES="${CASES:-"chains,pipelines"}"
}

test_chains() {
  echo "[test_chains]"

  ns="test-tekton-chains"
  echo "Reset namespace '$ns'"
  kubectl get namespace "$ns" >/dev/null && kubectl delete namespace "$ns"
  kubectl create namespace "$ns"
  kubectl apply -k "$SCRIPT_DIR/manifests/test/tekton-chains" -n "$ns"

  # Wait for pipelines to set up all the components
  while [ "$(kubectl get applications -n openshift-gitops tekton-chains -o json | jq -r ".status.sync.status")" != "Synced" ] || \
    [ "$(kubectl get serviceaccounts -n test-tekton-chains | grep -cE "^pipeline ")" != "1" ]; do
    echo -n "."
    sleep 2
  done
  echo "OK"

  # Trigger the pipeline
  image_src="quay.io/aptible/alpine:latest"
  image_name="$(basename "$image_src")"
  image_dst="image-registry.openshift-image-registry.svc:5000/$ns/$image_name"
  tkn -n "$ns" pipeline start simple-copy \
      --param image-src="$image_src" \
      --param image-dst="$image_dst" \
      --workspace name=shared,pvc,claimName="tekton-build" \
      --showlog
  pipeline_name="$(kubectl get -n "$ns" pipelineruns -o json | jq -r ".items[0].metadata.name")"

  echo -n "Pipeline signed: "
  signed="$(kubectl get pipelineruns -n "$ns" "$pipeline_name" -o jsonpath='{.metadata.annotations.chains\.tekton\.dev/signed}')"
  retry_timer=0
  polling_interval=2
  until [ -n "$signed" ] || [ "$retry_timer" -ge 30 ]; do
    echo -n "."
    sleep $polling_interval
    retry_timer=$(( retry_timer + polling_interval ))
    signed="$(kubectl get pipelineruns -n "$ns" "$pipeline_name" -o jsonpath='{.metadata.annotations.chains\.tekton\.dev/signed}')"
  done
  if [ "$signed" = "true" ]; then
    echo "OK"
  else
    echo "Failed"
    echo "[ERROR] Unsigned pipeline ($pipeline_name)" >&2
    exit 1
  fi

  echo -n "Image signed: "
  signed="$(kubectl get -n "$ns" imagestreamtags | grep -cE ":sha256-[0-9a-f]*\.att|:sha256-[0-9a-f]*\.sig" || true)"
  # No need to reset $retry_timer
  until [ "$signed" = "2" ] || [ "$retry_timer" -ge 30 ]; do
    echo -n "."
    sleep $polling_interval
    retry_timer=$(( retry_timer + polling_interval ))
    signed="$(kubectl get -n "$ns" imagestreamtags | grep -cE ":sha256-[0-9a-f]*\.att|:sha256-[0-9a-f]*\.sig" || true)"
  done
  if [ "$signed" = "2" ]; then
    echo "OK"
  else
    echo "Failed"
    echo "[ERROR] Unsigned image" >&2
    exit 1
  fi
  echo
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
  PIPELINE_RUN=$(curl --fail --silent "$BASE_URL/examples/v1beta1/$manifest" | sed 's|ubuntu|registry.access.redhat.com/ubi8/ubi-minimal:latest|' | sed '/serviceAccountName/d' | KUBECONFIG="$KUBECONFIG_KCP" kubectl create -f -)
  echo "$PIPELINE_RUN"
  
  KUBECONFIG="$KUBECONFIG_KCP" kubectl wait --for=condition=Succeeded  PipelineRun --all --timeout=60s >/dev/null
  echo "Print pipelines custom resources inside kcp"
  KUBECONFIG="$KUBECONFIG_KCP" kubectl get pipelineruns
  echo "Print kube resources in the physical cluster (Note: physical cluster will not know what pipelinesruns are)"
  
  KCP_NS_NAME="$(get_namespace)"
  kubectl get pods -n "$KCP_NS_NAME"

  echo
}

test_triggers() {
  echo "[test_triggers]"
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
  kill "$SVC_FORWARD_PID"
  sleep 20
  KUBECONFIG="$KUBECONFIG_KCP" kubectl get pipelineruns
  echo
}

test_results() {
  KCP_NS_NAME="$(get_namespace)"
  if [[ $PIPELINE_RUN == *"created"* ]]; then
    PIPELINE_RUN=$(echo "$PIPELINE_RUN" | grep -o -P '(?<=/).*(?= created)')
  fi
  echo "[verify_results]"
  echo "Verify tekton-results has stored the results in the database"

  # Prepare a custom Service Account that will be used for debugging purposes
  if ! KUBECONFIG="$KUBECONFIG" kubectl get serviceaccount tekton-results-debug -n tekton-results >/dev/null 2>&1; then
    KUBECONFIG="$KUBECONFIG" kubectl create serviceaccount tekton-results-debug -n tekton-results
  fi
  # Grant required privileges to the Service Account
  if ! KUBECONFIG="$KUBECONFIG" kubectl get clusterrolebinding tekton-results-debug -n tekton-results >/dev/null 2>&1; then
    KUBECONFIG="$KUBECONFIG" kubectl create clusterrolebinding tekton-results-debug --clusterrole=tekton-results-readonly --serviceaccount=tekton-results:tekton-results-debug
  fi

  # Proxies the remote Service to localhost.
  KUBECONFIG="$KUBECONFIG" kubectl port-forward -n tekton-results service/tekton-results-api-service 50051 >/dev/null & 
  PORTFORWARD_PID=$!
  echo "$PORTFORWARD_PID"
  # download the API Server certificate locally and configure gRPC.
  KUBECONFIG="$KUBECONFIG" kubectl get secrets tekton-results-tls -n tekton-results --template='{{index .data "tls.crt"}}' | base64 -d > /tmp/results.crt
  export GRPC_DEFAULT_SSL_ROOTS_FILE_PATH=/tmp/results.crt
  
  RESULT_UID=$(kubectl get pipelinerun "$PIPELINE_RUN" -n "$KCP_NS_NAME" -o yaml | yq .metadata.uid)
  
  # This is required to pass shellcheck due to the single quotes in the GetResult name parameter.
  QUERY="name: \"$KCP_NS_NAME/results/$RESULT_UID\""
  RECORD_CMD=(
    "grpc_cli"
    "call"
    "--channel_creds_type=ssl"
    "--ssl_target=tekton-results-api-service.tekton-results.svc.cluster.local"
    "--call_creds=access_token=$(kubectl get secrets -n tekton-results -o jsonpath="{.items[?(@.metadata.annotations['kubernetes\.io/service-account\.name']=='tekton-results-debug')].data.token}"| cut -d ' ' -f 2 | base64 --decode)"
    "localhost:50051"
    "tekton.results.v1alpha2.Results.GetResult"
    "'$QUERY'")
  RECORD_RESULT=$("${RECORD_CMD[@]}")

  # kill backgrounded port forwarding process as it is no longer required. 
  kill "$PORTFORWARD_PID"

  if [[ $RECORD_RESULT == *$RESULT_UID* ]]; then
    echo "OK"
  else
    echo "Failed"
    echo "[ERROR] Unable to retrieve record $RESULT_UID from pipeline run $PIPELINE_RUN" >&2
    exit 1
  fi
  echo
}

main() {
  prechecks
  init
  IFS="," read -r -a cases <<< "$CASES"
  for case in "${cases[@]}"
  do
    case $case in
    chains|pipelines|triggers)
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
