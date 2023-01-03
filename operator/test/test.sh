#!/usr/bin/env bash

#quit if exit status of any cmd is a non-zero value
set -euo pipefail

# Uncomment the below line to enable debugging
# set -x

usage() {

    printf "Usage: KUBECONFIG=/cluster.kubeconfig CASES=pipelines ./test.sh\n\n"

    # Parameters
    printf "KUBECONFIG: the path to the kubernetes KUBECONFIG file\n"
    printf "CASES: comma separated list of test cases. Test cases must be any of 'chains', 'pipelines' or 'triggers'. 'chains' and 'pipelines' are run by default.\n"
}

prechecks() {
    KUBECONFIG="${KUBECONFIG:-}"
    if [[ -z "$KUBECONFIG" ]]; then
        printf "KUBECONFIG is not set\n\n"
        usage
        exit 1
    fi
}

init() {
  SCRIPT_DIR=$(
    cd "$(dirname "$0")" >/dev/null
    pwd
  )
  export KUBECONFIG
  CASES="${CASES:-"chains,pipelines"}"
  PIPELINES_NS="pipelines-test"
}

test_chains() {
  echo "[test_chains]"

  ns="test-tekton-chains"
  echo "Reset namespace '$ns'"
  kubectl get namespace "$ns" >/dev/null && kubectl delete namespace "$ns"
  kubectl create namespace "$ns"
  kubectl apply -k "$SCRIPT_DIR/manifests/test/tekton-chains" -n "$ns"

  # Wait for pipelines to set up all the components
  while [ "$(kubectl get serviceaccounts -n test-tekton-chains | grep -cE "^pipeline ")" != "1" ]; do
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
  if ! kubectl get namespace $PIPELINES_NS >/dev/null 2>&1; then
    kubectl create namespace $PIPELINES_NS
  fi
  if ! kubectl get -n $PIPELINES_NS serviceaccount default >/dev/null 2>&1; then
    kubectl create -n $PIPELINES_NS  serviceaccount default
  fi
  BASE_URL="https://raw.githubusercontent.com/tektoncd/pipeline/v0.32.0"
  manifest="pipelineruns/using_context_variables.yaml"
  # change ubuntu image to ubi to avoid dockerhub registry pull limit
  PIPELINE_RUN=$(
    curl --fail --silent "$BASE_URL/examples/v1beta1/$manifest" |
      sed 's|ubuntu|registry.access.redhat.com/ubi9/ubi-minimal:latest|' |
      sed '/serviceAccountName/d' |
      kubectl create -n $PIPELINES_NS -f -
  )
  echo "$PIPELINE_RUN"

  kubectl wait --for=condition=Succeeded  -n $PIPELINES_NS PipelineRun --all --timeout=60s >/dev/null
  echo "Print pipelines"
  kubectl get -n $PIPELINES_NS pipelineruns
}

test_triggers() {
  echo "[test_triggers]"
  echo "Simulating a Github PR through a curl request which creates a TaskRun (from tektoncd/triggers/examples)"
  kubectl apply -f https://raw.githubusercontent.com/tektoncd/triggers/v0.18.0/examples/v1beta1/github/github-eventlistener-interceptor.yaml
  kubectl apply -f https://raw.githubusercontent.com/tektoncd/triggers/v0.18.0/examples/v1beta1/github/secret.yaml
  sleep 20
  # Simulate the behaviour of a webhook. GitHub sends some payload and trigger a TaskRun.
  kubectl port-forward service/el-github-listener 8089:8080 &
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
  kubectl get pipelineruns
  echo
}

test_results() {
  if [[ $PIPELINE_RUN == *"created"* ]]; then
    PIPELINE_RUN=$(echo "$PIPELINE_RUN" | grep -o -P '(?<=/).*(?= created)')
  fi
  echo "[verify_results]"
  echo "Verify tekton-results has stored the results in the database"

  # Prepare a custom Service Account that will be used for debugging purposes
  if ! kubectl get serviceaccount tekton-results-debug -n tekton-results >/dev/null 2>&1; then
    kubectl create serviceaccount tekton-results-debug -n tekton-results
  fi
  # Grant required privileges to the Service Account
  if ! kubectl get clusterrolebinding tekton-results-debug -n tekton-results >/dev/null 2>&1; then
    kubectl create clusterrolebinding tekton-results-debug --clusterrole=tekton-results-readonly --serviceaccount=tekton-results:tekton-results-debug
  fi

  # Proxies the remote Service to localhost.
  kubectl port-forward -n tekton-results service/tekton-results-api-service 50051 >/dev/null & 
  PORTFORWARD_PID=$!
  echo "$PORTFORWARD_PID"
  # download the API Server certificate locally and configure gRPC.
  kubectl get secrets tekton-results-tls -n tekton-results --template='{{index .data "tls.crt"}}' | base64 -d > /tmp/results.crt
  export GRPC_DEFAULT_SSL_ROOTS_FILE_PATH=/tmp/results.crt
  
  RESULT_UID=$(kubectl get pipelinerun "$PIPELINE_RUN" -n $PIPELINES_NS -o yaml | yq .metadata.uid)
  
  # This is required to pass shellcheck due to the single quotes in the GetResult name parameter.
  QUERY="name: \"$PIPELINES_NS/results/$RESULT_UID\""
  RECORD_CMD=(
    "grpc_cli"
    "call"
    "--channel_creds_type=ssl"
    "--ssl_target=tekton-results-api-service.tekton-results.svc.cluster.local"
    "--call_creds=access_token=$(kubectl get secrets -n tekton-results -o jsonpath="{.items[?(@.metadata.annotations['kubernetes\.io/service-account\.name']=='tekton-results-debug')].data.token}"| cut -d ' ' -f 2 | base64 --decode)"
    "localhost:50051"
    "tekton.results.v1alpha2.Results.GetResult"
    "$QUERY")
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
    chains|pipelines|results|triggers)
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
