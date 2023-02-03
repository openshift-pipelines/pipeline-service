#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

usage() {
    echo "
Usage:
    ${0##*/} [options]

Check if a PR is required to submit commited changes.
The environment variable GITHUB_TOKEN must be set with a token that
allows the PRs in the repository to be read.

Mandatory arguments:
    -b, --target_branch
        Branch to open against which the PR is opened.
    -n, --name
        Repository name.
    -o, --onwer
        Repository owner.

Optional arguments:
    -r, --result
        File in which to write the result.
        Default: /dev/stdout
    -d, --debug
        Activate tracing/debug mode.
    -h, --help
        Display this message.

Example:
    ${0##*/} --owner openshift-pipelines --name pipeline-service --target_branch main
" >&2
}

parse_args() {
    RESULT="/dev/stdout"
    while [[ $# -gt 0 ]]; do
        case $1 in
        -n | --name)
            shift
            REPO_NAME="$1"
            ;;
        -o | --owner)
            shift
            REPO_OWNER="$1"
            ;;
        -b | --target_branch)
            shift
            REPO_TARGET_BRANCH="$1"
            ;;
        -r | --result)
            shift
            RESULT="$1"
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

prechecks() {
    if [[ -z "${REPO_NAME:-}" ]]; then
      printf "\n[ERROR] Missing parameter --name" >&2
      exit 1
    fi
    if [[ -z "${REPO_OWNER:-}" ]]; then
      printf "\n[ERROR] Missing parameter --owner" >&2
      exit 1
    fi
    if [[ -z "${REPO_TARGET_BRANCH:-}" ]]; then
      printf "\n[ERROR] Missing parameter --target_branch" >&2
      exit 1
    fi
}

run() {
    prechecks
    if git diff --quiet "$REPO_TARGET_BRANCH"; then
        # No diff
        printf "yes" >"$RESULT"
        exit
    fi

    IS_PR_CREATED=$(
        curl \
            --data-urlencode "head=$REPO_OWNER:$REPO_TARGET_BRANCH" \
            --fail \
            --get \
            --header "Accept: application/vnd.github+json" \
            --header "Authorization: Bearer $GITHUB_TOKEN" \
            --silent \
            "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/pulls" |
            jq ". | length"
    )
    if [ "$IS_PR_CREATED" = "0" ]; then
        printf "no"
    else
        # PR already opened
        printf "yes"
    fi >"$RESULT"
}

main() {
    parse_args "$@"
    run
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
    main "$@"
fi
