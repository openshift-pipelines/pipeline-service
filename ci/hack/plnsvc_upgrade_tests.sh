#!/usr/bin/env bash

#quit if exit status of any cmd is a non-zero value
set -o errexit
set -o nounset
set -o pipefail

usage() {
    echo "
Usage:
    $0 [options]

Run Pipeline Service upgrade tests on the cluster referenced by KUBECONFIG.

Using the 'main' branch as the baseline, it will deploy Pipeline Service,
upgrade to your current branch, and downgrade back to 'main', testing the
service at every step along the way.

Optional arguments:
    -k, --kubeconfig KUBECONFIG
        kubeconfig to the cluster to test.
        The current context will be used.
        Default value: \$KUBECONFIG"
    # -f, --from VERSION
    #     Branch, SHA or tag of the base version.
    #     Default: main.
    # -t, --to VERSION
    #     Branch, SHA or tag of the new version.
    #     Default: Current commit.
echo "\
    -d, --debug
        Activate tracing/debug mode.
    -h, --help
        Display this message.

Example:
    $0 --kubeconfig mykubeconfig.yaml
"
}

parse_args() {
    KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
    FROM_VERSION="main"
    TO_VERSION=$(git branch --show-current)
    while [[ $# -gt 0 ]]; do
        case $1 in
        -k | --kubeconfig)
        shift
        KUBECONFIG="$1"
        ;;
        # -f | --from)
        #   shift
        #   FROM_VERSION="$1"
        #   ;;
        # -t | --to)
        #   shift
        #   TO_VERSION="$1"
        #   ;;
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
}

init() {
    SCRIPT_DIR=$(
        cd "$(dirname "$0")" >/dev/null
        pwd
    )
    PROJECT_DIR=$(
        cd "$SCRIPT_DIR/../.." >/dev/null
        pwd
    )
    export KUBECONFIG
}

run_for(){
    OPTS=""
    case "$1" in
        from)
            VERSION="$FROM_VERSION"
            ;;
        to)
            VERSION="$TO_VERSION"
            OPTS="--use-current-branch"
            ;;
    esac
    echo
    git checkout "$VERSION"
    echo "[Deploying $VERSION]"
    # shellcheck disable=SC2086
    "$PROJECT_DIR/developer/openshift/dev_setup.sh" $OPTS $DEBUG

    echo
    echo "[Testing $VERSION]"
    # shellcheck disable=SC2086
    "$PROJECT_DIR/operator/test/test.sh" $DEBUG
}

on_exit(){
    git checkout -f "$TO_VERSION"
    [ "$STASH" == "1" ] || git stash pop
}

main() {
    parse_args "$@"
    init

    trap on_exit EXIT

    STASH="$(git stash | grep -c "No local changes to save" || true)"

    run_for "from"
    run_for "to"
    run_for "from"
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
    main "$@"
fi
