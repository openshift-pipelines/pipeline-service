#!/usr/bin/env bash

#quit if exit status of any cmd is a non-zero value
set -o errexit
set -o nounset
set -o pipefail
set -x

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
        Must be one of: chains, pipelines, results, security, metrics.
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
  DEBUG_OUTPUT="/dev/null"
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
      DEBUG_OUTPUT="/dev/stdout"
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
    TEST_LIST=("chains" "pipelines" "results" "security" "metrics")
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
  kubectl apply -k "$SCRIPT_DIR/manifests/setup/pipeline-service" >"$DEBUG_OUTPUT"
  echo "OK"
  echo
}

wait_for_pipeline() {
  if ! kubectl wait --for=condition=succeeded "$1" -n "$2" --timeout 300s >"$DEBUG_OUTPUT"; then
    echo "[ERROR] Pipeline failed to complete successful" >&2
    kubectl get pipelineruns "$1" -n "$2" >"$DEBUG_OUTPUT"
    exit 1
  fi
}

check_pod_security() {
  mapfile -t pods < <(kubectl get pod -o name -n "$1")
  for pod in "${pods[@]}"; do
    if [[ "$pod" == "pod/storage-pool-0-0" ]] || [[ "$pod" == "pod/postgres-postgresql-0" ]]; then
      echo "   - Skip: $pod is exempt"
      continue
    fi
    scc="$(kubectl get "$pod" -o jsonpath='{.metadata.annotations.openshift\.io/scc}' -n "$1"  --ignore-not-found)"
    if [ -z "$scc" ]; then
      echo "   - Skip: $pod could not be inspected (most like the pod terminated quickly)"
      continue
    fi
    if [[ "$scc" =~ "restricted" ]]; then
      echo "   - OK pod security check for $pod with scc $scc"
      continue
    fi
    echo "[ERROR] Unexpected scc $scc for pod $pod"
    securityErrorFound="yes"
  done
}

check_host_network() {
  mapfile -t pods < <(kubectl get pod -o name -n "$1")
  for pod in "${pods[@]}"; do
    # got to '|| true' or the script exits with the rc 1 that grep returns if nothing found
    hostipc="$(kubectl get "$pod" -o yaml -n "$1"  --ignore-not-found | grep "hostIPC" || true )"
    if [ -z "$hostipc" ]; then
      echo "   - OK hostIPC settings for $pod"
    else
       echo "Failed, hostIPC's are "
       echo "$hostipc"
       echo "[ERROR] Unexpected $pod hostIPC settings" >&2
       securityErrorFound="yes"
    fi
    hostpid="$(kubectl get "$pod" -o yaml -n "$1"  --ignore-not-found | grep "hostPID" || true )"
    if [ -z "$hostpid" ]; then
      echo "   - OK hostPID settings for $pod"
    else
       echo "Failed, hostPID's are "
       echo "$hostpid"
       echo "[ERROR] Unexpected $pod hostPID settings" >&2
       securityErrorFound="yes"
    fi
  done
}

test_metrics() {
  prName="$(kubectl create -n "$NAMESPACE" -f "$SCRIPT_DIR/manifests/test/metrics/curl-metrics-service-pipeline.yaml" | awk '{print $1}')"
  echo "Checking $prName for metric output"
  wait_for_pipeline "$prName" "$NAMESPACE"
  echo "OK"
}

test_chains() {
  kubectl apply -k "$SCRIPT_DIR/manifests/test/tekton-chains" -n "$NAMESPACE" >"$DEBUG_OUTPUT"
  while ! kubectl get pipelines -n "$NAMESPACE" -o name 2>/dev/null | grep -q "pipeline.tekton.dev/simple-copy"; do
    echo -n "."
    sleep 5
  done

  echo -n "  - Signing secret: "
  if ! kubectl get secret signing-secrets -n openshift-pipelines >/dev/null 2>&1; then
    echo "Failed"
    echo "[ERROR] Secret does not exist" >&2
    exit 1
  fi
  if [ "$(kubectl get secret signing-secrets -n openshift-pipelines -o jsonpath='{.immutable}')" != "true" ]; then
    echo "Failed"
    echo "[ERROR] Secret is not immutable" >&2
    exit 1
  fi
  echo "OK"

  # Trigger the pipeline
  echo -n "  - Run pipeline: "
  image_src="quay.io/aptible/alpine:latest"
  image_name="$(basename "$image_src")"
  image_dst="image-registry.openshift-image-registry.svc:5000/$NAMESPACE/$image_name"
  pipeline_name="$(
    tkn -n "$NAMESPACE" pipeline start simple-copy \
      --param image-src="$image_src" \
      --param image-dst="$image_dst" \
      --serviceaccount "chains-test" \
      --workspace name=shared,pvc,claimName="tekton-build" |
      head -1 | sed "s:.* ::"
  )"
  wait_for_pipeline "pipelineruns/$pipeline_name" "$NAMESPACE"
  echo "OK"

  echo -n "  - Pipeline signed: "
  signed="$(kubectl get pipelineruns -n "$NAMESPACE" "$pipeline_name" -o jsonpath='{.metadata.annotations.chains\.tekton\.dev/signed}')"
  retry_timer=0
  polling_interval=2
  until [ -n "$signed" ] || [ "$retry_timer" -ge 300 ]; do
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
  echo "Skip"
  # signed="$(kubectl get -n "$NAMESPACE" imagestreamtags | grep -cE ":sha256-[0-9a-f]*\.att|:sha256-[0-9a-f]*\.sig" || true)"
  # # No need to reset $retry_timer
  # until [ "$signed" = "2" ] || [ "$retry_timer" -ge 30 ]; do
  #   echo -n "."
  #   sleep $polling_interval
  #   retry_timer=$((retry_timer + polling_interval))
  #   signed="$(kubectl get -n "$NAMESPACE" imagestreamtags | grep -cE ":sha256-[0-9a-f]*\.att|:sha256-[0-9a-f]*\.sig" || true)"
  # done
  # if [ "$signed" = "2" ]; then
  #   echo "OK"
  # else
  #   echo "Failed"
  #   echo "[ERROR] Unsigned image" >&2
  #   exit 1
  # fi

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

  # TODO: Reactivate on step 2/3 of the migration.
  # This test is not critical until we ask EC to use the openshift-pipelines namespace.
  # echo -n "  - Public key migration: "
  # pipeline_name=$(kubectl create -f "$SCRIPT_DIR/manifests/test/tekton-chains/public-key-migration.yaml" -n "$NAMESPACE" | cut -d' ' -f1)
  # wait_for_pipeline "$pipeline_name" "$NAMESPACE"
  # if [ "$(kubectl get "$pipeline_name" -n "$NAMESPACE" \
  #   -o 'jsonpath={.status.conditions[0].reason}')" = "Succeeded" ]; then
  #   echo "OK"
  # else
  #   echo "Failed"
  #   echo "[ERROR] Public key is not accessible" >&2
  #   exit 1
  # fi

  echo -n "  - Metrics: "
  prName="$(kubectl create -n "$NAMESPACE" -f "$SCRIPT_DIR/manifests/test/tekton-chains/tekton-chains-metrics.yaml" | awk '{print $1}')"
  wait_for_pipeline "$prName" "$NAMESPACE"
    if [ "$(kubectl get "$prName" -n "$NAMESPACE" \
    -o 'jsonpath={.status.conditions[0].reason}')" = "Succeeded" ]; then
    echo "OK"
  else
    echo "Failed"
    echo "[ERROR] Tekton Chains metrics is not available/working" >&2
    exit 1
  fi

  echo
}

test_pipelines() {
  echo -n "  - Run pipeline: "
  if ! kubectl get -n "$NAMESPACE" serviceaccount default >"$DEBUG_OUTPUT" 2>&1; then
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
  export securityErrorFound=""
  echo " - Check security: "
  echo "  - Check Pod Security openshift-pipelines: "
  check_pod_security "openshift-pipelines"
  echo "  - Check Pod Host Network openshift-pipelines: "
  check_host_network "openshift-pipelines"

  echo "  - Check Pod Security tekton-results: "
  check_pod_security "tekton-results"
  echo "  - Check Pod Host Network tekton-results: "
  check_host_network "tekton-results"

  if [[ "$securityErrorFound" == "yes" ]]; then
    echo " - Check security failed"
    exit 1
  fi

}

test_results() {
  # Check logs for OCP bug https://issues.redhat.com/browse/OCPBUGS-5916
  printf "\n  - Check HTTP2 health probe errors: "
  pattern="http2: server: error reading preface from client"
  if kubectl logs deployment/tekton-results-api -c "api" -n "$NAMESPACE" 2>/dev/null | grep -ciq "$pattern"; then
    echo "Failed"
    exit 1
  else
    echo "OK"
  fi

  test_pipelines
  echo -n "  - Results in database:"

  # Service Account to test tekton-results
  if ! kubectl get serviceaccount "$RESULTS_SA" -n "$NAMESPACE" >"$DEBUG_OUTPUT" 2>&1; then
    kubectl create serviceaccount "$RESULTS_SA" -n "$NAMESPACE"
    echo -n "."
  fi
  # Grant required privileges to the Service Account
  if ! kubectl get rolebinding tekton-results-tests -n "$NAMESPACE" >"$DEBUG_OUTPUT" 2>&1; then
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

      if ! echo "$LOGS_RESULT" | grep -qF "PipelineRun name from params:" ; then
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
    chains | pipelines | results | security | metrics)
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
