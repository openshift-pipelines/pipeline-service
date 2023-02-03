#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

usage() {
    echo "
Usage:
    ${0##*/} [options]

Setup the CI git environment.

Optional arguments:
    -b, --branch
        Branch to checkout.
        Default: main.
    -d, --debug
        Activate tracing/debug mode.
    -h, --help
        Display this message.

Example:
    ${0##*/}
" >&2
}

parse_args() {
    REPO_SOURCE_BRANCH="main"
    while [[ $# -gt 0 ]]; do
        case $1 in
        -b | --branch)
            shift
            REPO_SOURCE_BRANCH="$1"
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

run() {
    # Setup user
    git config --local user.email "pipeline-service@example.com"
    git config --local user.name "Pipeline Service CI Robot"

    # Use SSH authentication
    git config --replace-all remote.origin.url "$(
        git config --get remote.origin.url |
            sed -e "s|^https\?://github.com/|git@github.com:|" -e "s|\(\.git\)\?$|.git|"
    )"

    # Set the branch
    git checkout -b "$REPO_SOURCE_BRANCH"
}

main() {
    parse_args "$@"
    run
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
    main "$@"
fi
