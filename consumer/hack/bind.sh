#!/usr/bin/env bash

#quit if exit status of any cmd is a non-zero value
set -euo pipefail

SCRIPT_DIR="$(
    cd "$(dirname "$0")" >/dev/null
    pwd
)"

# shellcheck source=consumer/hack/run_test_workload.sh
source "$SCRIPT_DIR/run_test_workload.sh"

usage() {
    echo "
Usage:
    ${0##*/} [options]

Setup Pipeline Service on a kcp workspace.

Mandatory arguments:
    -f, --from SERVICE_WORKSPACE
        Path to the workspace exposing the APIExport.

Optional arguments:
    -k, --kubeconfig KUBECONFIG
        Path to the kubeconfig with the connection information to the kcp workspace.
    -t, --to SERVICE_WORKSPACE
        Workspace in which to bind the pipeline service.
        Default: Current workspace defined in KUBECONFIG
    -d, --debug
        Activate tracing/debug mode.
    -h, --help
        Display this message.

Example:
    ${0##*/} --from root:pipeline-service --to '~:pipeline-service-test'
" >&2
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
        -k | --kubeconfig)
            shift
            KUBECONFIG="$1"
            ;;
        -f | --from)
            shift
            SERVICE_WORKSPACE="$1"
            ;;
        -to | --to)
            shift
            WORKSPACE="$1"
            ;;
        -d | --debug)
            set -x
            DEBUG="--debug"
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
    if [ -z "$SERVICE_WORKSPACE" ]; then
        echo "Unset variable: SERVICE_WORSPACE" >&2
        usage
        exit 1
    fi

    DEBUG=${DEBUG:-}
    export KUBECONFIG=${KUBECONFIG:-$HOME/.kube/config}
    WORKSPACE=${WORKSPACE:-}
}

bind_to_service() {
    yq '.spec.reference.workspace.path = "'"$SERVICE_WORKSPACE"'"' "$SCRIPT_DIR/../manifests/apibinding/apibinding.yaml" | kubectl apply -f -
}

main() {
    parse_args "$@"
    init

    go_to_workspace
    bind_to_service
    run_test
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
    main "$@"
fi
