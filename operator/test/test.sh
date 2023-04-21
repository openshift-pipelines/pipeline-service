#!/usr/bin/env bash

#quit if exit status of any cmd is a non-zero value
set -o errexit
set -o nounset
set -o pipefail

usage() {
  echo "
Usage:
    $0 [options]

Run Pipeline Service tests on the cluster referenced by KUBECONFIG.

Optional arguments:
    -k, --kubeconfig KUBECONFIG
        kubeconfig to the cluster to test.
        The current context will be used.
        Default value: \$KUBECONFIG
    -t, --test TEST
        Name of the test to be executed. Can be repeated to run multiple tests.
        Must be one of: chains, pipelines, results, security.
        Default: Run all tests.
    -d, --debug
        Activate tracing/debug mode.
    -h, --help
        Display this message.

Example:
    $0 --kubeconfig mykubeconfig.yaml --test chains --test pipelines
"
}

parse_args() {
  KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
  TEST_LIST=()
  while [[ $# -gt 0 ]]; do
    case $1 in
    -k | --kubeconfig)
      shift
      KUBECONFIG="$1"
      ;;
    -t | --test)
      shift
      TEST_LIST+=("$1")
      ;;
    -d | --debug)
      DEBUG="--debug"
      set -x
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
    esac
    shift
  done
  DEBUG="${DEBUG:-}"
  if [ "${#TEST_LIST[@]}" = "0" ]; then
    TEST_LIST=("chains" "pipelines" "results" "security")
  fi
}

init() {
  SCRIPT_DIR=$(
    cd "$(dirname "$0")" >/dev/null
    pwd
  )
  export KUBECONFIG
  NAMESPACE="plnsvc-tests"
  RESULTS_SA="tekton-results-tests"
}

setup_test() {
  echo "[Setup]"
  echo -n "  - Namespace configuration: "
  if ! kubectl get namespace $NAMESPACE >/dev/null 2>&1; then
    echo -n "."
    kubectl create namespace "$NAMESPACE" >/dev/null
  fi
  # Wait for pipelines to set up all the components
  while [ "$(kubectl get serviceaccounts -n "$NAMESPACE" | grep -cE "^pipeline ")" != "1" ]; do
    echo -n "."
    sleep 2
  done
  echo "OK"
  echo
}

wait_for_pipeline() {
  kubectl wait --for=condition=succeeded "$1" -n "$2" --timeout 60s >/dev/null
}

check_pod_security() {
  sccs="$(kubectl get pod -o name -n "$1" | xargs -l -r kubectl get -o jsonpath='{.metadata.annotations.openshift\.io/scc}' -n "$1")"
  if [[ "$sccs" =~ "restricted-v2" ]]; then
     prune="$(echo "$sccs" | sed 's/restricted-v2//g')"
     # if anything besides restricted-v2 is in there, we want to investigate
     if [ -z "$prune" ]; then
       echo "   - OK pod security for $1"
     else
       echo "Failed, scc's are "
       echo "$sccs"
       echo "[ERROR] Unexpected $1 pod security context constraints" >&2
       exit 1
     fi
  else
     # if none of the pods are restricted-v2, we want to investigate
     echo "Failed, scc's are "
     echo "$sccs"
     echo "[ERROR] Unexpected $1 pod security context constraints" >&2
     exit 1
  fi

}

check_host_network() {
  # got to '|| true' or the script exits with the rc 1 that grep returns if nothing found
  hostipc="$(kubectl get pods -o yaml -n "$1" | grep "hostIPC" || true )"
  if [ -z "$hostipc" ]; then
    echo "   - OK hostIPC settings for $1"
  else
       echo "Failed, hostIPC's are "
       echo "$hostipc"
       echo "[ERROR] Unexpected $1 hostIPC settings" >&2
       exit 1
  fi
  hostpid="$(kubectl get pods -o yaml -n "$1" | grep "hostPID" || true )"
  if [ -z "$hostpid" ]; then
    echo "   - OK hostPID settings for $1"
  else
       echo "Failed, hostPID's are "
       echo "$hostipc"
       echo "[ERROR] Unexpected $1 hostPID settings" >&2
       exit 1
  fi
  hostnetwork="$(kubectl get pods -o yaml -n "$1" | grep "hostNetwork" || true )"
  if [ -z "$hostnetwork" ]; then
    echo "   - OK hostNetwork settings for $1"
  else
       echo "Failed, hostNetwork's are "
       echo "$hostnetwork"
       echo "[ERROR] Unexpected $1 hostNetwork settings" >&2
       exit 1
  fi
}

test_chains() {
  kubectl apply -k "$SCRIPT_DIR/manifests/test/tekton-chains" -n "$NAMESPACE" >/dev/null

  # Trigger the pipeline
  echo -n "  - Run pipeline: "
  image_src="quay.io/aptible/alpine:latest"
  image_name="$(basename "$image_src")"
  image_dst="image-registry.openshift-image-registry.svc:5000/$NAMESPACE/$image_name"
  pipeline_name="$(
    tkn -n "$NAMESPACE" pipeline start simple-copy \
      --param image-src="$image_src" \
      --param image-dst="$image_dst" \
      --workspace name=shared,pvc,claimName="tekton-build" |
      head -1 | sed "s:.* ::"
  )"
  wait_for_pipeline "pipelineruns/$pipeline_name" "$NAMESPACE"
  echo "OK"

  echo -n "  - Pipeline signed: "
  signed="$(kubectl get pipelineruns -n "$NAMESPACE" "$pipeline_name" -o jsonpath='{.metadata.annotations.chains\.tekton\.dev/signed}')"
  retry_timer=0
  polling_interval=2
  until [ -n "$signed" ] || [ "$retry_timer" -ge 30 ]; do
    echo -n "."
    sleep $polling_interval
    retry_timer=$((retry_timer + polling_interval))
    signed="$(kubectl get pipelineruns -n "$NAMESPACE" "$pipeline_name" -o jsonpath='{.metadata.annotations.chains\.tekton\.dev/signed}')"
  done
  if [ "$signed" = "true" ]; then
    echo "OK"
  else
    echo "Failed"
    echo "[ERROR] Unsigned pipeline ($pipeline_name)" >&2
    exit 1
  fi

  echo -n "  - Image signed: "
  signed="$(kubectl get -n "$NAMESPACE" imagestreamtags | grep -cE ":sha256-[0-9a-f]*\.att|:sha256-[0-9a-f]*\.sig" || true)"
  # No need to reset $retry_timer
  until [ "$signed" = "2" ] || [ "$retry_timer" -ge 30 ]; do
    echo -n "."
    sleep $polling_interval
    retry_timer=$((retry_timer + polling_interval))
    signed="$(kubectl get -n "$NAMESPACE" imagestreamtags | grep -cE ":sha256-[0-9a-f]*\.att|:sha256-[0-9a-f]*\.sig" || true)"
  done
  if [ "$signed" = "2" ]; then
    echo "OK"
  else
    echo "Failed"
    echo "[ERROR] Unsigned image" >&2
    exit 1
  fi

  echo -n "  - Public key: "
  pipeline_name=$(kubectl create -f "$SCRIPT_DIR/manifests/test/tekton-chains/public-key.yaml" -n "$NAMESPACE" | cut -d' ' -f1)
  wait_for_pipeline "$pipeline_name" "$NAMESPACE"
  if [ "$(kubectl get "$pipeline_name" -n "$NAMESPACE" \
    -o 'jsonpath={.status.conditions[0].reason}')" = "Succeeded" ]; then
    echo "OK"
  else
    echo "Failed"
    echo "[ERROR] Public key is not accessible" >&2
    exit 1
  fi

  echo
}

test_pipelines() {
  echo -n "  - Run pipeline: "
  if ! kubectl get -n "$NAMESPACE" serviceaccount default >/dev/null 2>&1; then
    kubectl create -n "$NAMESPACE" serviceaccount default
  fi
  BASE_URL="https://raw.githubusercontent.com/tektoncd/pipeline/v0.32.0"
  manifest="pipelineruns/using_context_variables.yaml"
  # change ubuntu image to ubi to avoid dockerhub registry pull limit
  pipeline_name=$(
    curl --fail --silent "$BASE_URL/examples/v1beta1/$manifest" |
      sed 's|ubuntu|registry.access.redhat.com/ubi9/ubi-minimal:latest|' |
      sed '/serviceAccountName/d' |
      kubectl create -n "$NAMESPACE" -f - | cut -d" " -f1
  )
  wait_for_pipeline "$pipeline_name" "$NAMESPACE"

  echo "OK"
}

test_security() {
  echo " - Check security: "
  echo "  - Check Pod Security openshift-pipelines: "
  check_pod_security "openshift-pipelines"
  echo "  - Check Pod Host Network openshift-pipelines: "
  check_host_network "openshift-pipelines"

  echo "  - Check Pod Security tekton-results: "
  check_pod_security "tekton-results"
  echo "  - Check Pod Host Network tekton-results: "
  check_host_network "tekton-results"

  echo "  - Check Pod Security tekton-chains: "
  check_pod_security "tekton-chains"
  echo "  - Check Pod Host Network tekton-chains: "
  check_host_network "tekton-chains"
}

test_results() {
  test_pipelines
  echo -n "  - Results in database:"

  # Service Account to test tekton-results
  if ! kubectl get serviceaccount "$RESULTS_SA" -n "$NAMESPACE" >/dev/null 2>&1; then
    kubectl create serviceaccount "$RESULTS_SA" -n "$NAMESPACE"
    echo -n "."
  fi
  # Grant required privileges to the Service Account
  if ! kubectl get rolebinding tekton-results-tests -n "$NAMESPACE" >/dev/null 2>&1; then
    kubectl create rolebinding tekton-results-tests -n "$NAMESPACE" --clusterrole=tekton-results-readonly --serviceaccount="$NAMESPACE":"$RESULTS_SA"
    echo -n "."
  fi

  RESULT_UID=$(kubectl get "$pipeline_name" -n "$NAMESPACE" -o yaml | yq .metadata.uid)

  # create a token associated with a service account
  token=$(kubectl create token "$RESULTS_SA" -n "$NAMESPACE")

  fetch_results_using_rest() {
    echo -n "    - Test $1: "
    # use exposed route for querying results API
    RESULT_ROUTE=$(kubectl get route tekton-results -n tekton-results --template='{{.spec.host}}')
    QUERY_URL="https://$RESULT_ROUTE/apis/results.tekton.dev/v1alpha2/parents/$NAMESPACE/results/$RESULT_UID/$1"

    QUERY_CMD=(
      "curl"
      "--insecure"
      "-H"
      "Authorization: Bearer $token"
      "-H"
      "Accept: application/json"
      "$QUERY_URL"
    )
    QUERY_RESULT=$("${QUERY_CMD[@]}" 2>/dev/null)
    wait

    # we are not interested in the content of the logs or records so just checking if the query result contains certain string (uid/type) 
    if [[ $QUERY_RESULT == *"$RESULT_UID/$1"* ]]; then
      echo "OK"
    else
      echo "Failed"
      echo "[ERROR] Unable to retrieve $1 for $RESULT_UID from pipeline run $pipeline_name" >&2
      exit 1
    fi

    # Let's make request to get log output and check it.
    if [ "${1}" == "logs" ]; then
      LOG_PATH=$(echo "${QUERY_RESULT}" | jq -r ".records[0] | .name")

      QUERY_URL="https://$RESULT_ROUTE/apis/results.tekton.dev/v1alpha2/parents/${LOG_PATH}"
      QUERY_CMD[6]="${QUERY_URL}"
      LOGS_RESULT=$("${QUERY_CMD[@]}" 2>/dev/null)
      LOGS_OUTPUT=$(echo "$LOGS_RESULT" | jq -r ".result.data | @base64d")

      if ! echo "$LOGS_OUTPUT" | grep -qF "PipelineRun name from params:" ; then
          echo "[ERROR] Unable to retrieve logs output."
          printf "[ERROR] Log record: %s \n" "${LOGS_RESULT}"
          exit 1
      fi
    fi
  }

  echo
  # test both "records" and "logs" endpoints 
  sleep 10
  fetch_results_using_rest "records"
  fetch_results_using_rest "logs"

  echo
}

main() {
  parse_args "$@"
  init
  setup_test
  for case in "${TEST_LIST[@]}"; do
    case $case in
    chains | pipelines | results | security)
      echo "[$case]"
      test_"$case"
      echo
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
