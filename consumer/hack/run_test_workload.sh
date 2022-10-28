#!/usr/bin/env bash

#quit if exit status of any cmd is a non-zero value
set -euo pipefail

SCRIPT_DIR="$(
    cd "$(dirname "$0")" >/dev/null
    pwd
)"

usage() {
    echo "
Usage:
    ${0##*/} [options]

Setup Pipeline Service on a kcp workspace.

Optional arguments:
    -k, --kubeconfig KUBECONFIG
        Path to the kubeconfig with the connection information to the kcp workspace.
    -w, --workspace WORKSPACE
        Workspace in which to run the test.
        Default: Current workspace defined in KUBECONFIG
    -d, --debug
        Activate tracing/debug mode.
    -h, --help
        Display this message.

Example:
    ${0##*/} --workspace root:my:user root:pipeline-service
" >&2
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
        -k | --kubeconfig)
            shift
            KUBECONFIG="$1"
            ;;
        -w | --workspace)
            shift
            WORKSPACE="$1"
            ;;
        -d | --debug)
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
}

init() {
    export KUBECONFIG=${KUBECONFIG:-$HOME/.kube/config}
    WORKSPACE=${WORKSPACE:-}
}

go_to_workspace() {
    if [ "$(kubectl ws current | cut -d\" -f2)" = "$WORKSPACE" ]; then
        # Already in the expected workspace
        return
    fi
    if kubectl ws use "$WORKSPACE" 2>/dev/null; then
        # Workspace exists and user has access
        return
    fi
    # Try to create and access the workspace
    PARENT_WORKSPACE="$(echo "$WORKSPACE" | sed 's/:[^:]*$//')"
    kubectl ws use "$PARENT_WORKSPACE"
    kubectl ws use "${WORKSPACE/*:/}" 2>/dev/null || kubectl ws create --enter "${WORKSPACE/*:/}"
}

create_namespace() {
    ns="test-workload-$(sha1sum <<<$RANDOM | cut -c 1-5)"
    kubectl create namespace "$ns"
    # Wait for the 'pipeline' service account to be created on the compute
    sleep 5
}

run_pipelinerun() {
    pipelinerun=$(kubectl create --namespace "$ns" -f "$SCRIPT_DIR/../manifests/workloads/hello-world.yaml" | cut -d" " -f 1)
    while [ "$(kubectl get pipelineruns --namespace "$ns" -o name | wc -l)" != "1" ]; do
        sleep 2
    done
    kubectl wait --namespace "$ns" "$pipelinerun" --for=condition=Succeeded --timeout 60s >/dev/null || echo "[ERROR] The workload did not run as expected" >&2
    echo
    echo "kubectl get pipelineruns --namespace $ns:"
    kubectl get pipelineruns --namespace "$ns"
    echo
}

delete_namespace() {
    kubectl delete namespace "$ns"
}

run_test() {
    create_namespace
    run_pipelinerun
    delete_namespace
}

main() {
    parse_args "$@"
    init

    go_to_workspace
    run_test
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
    main "$@"
fi
