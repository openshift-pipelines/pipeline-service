#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(
  cd "$(dirname "$0")" >/dev/null
  pwd
)"

# shellcheck source=operator/images/update-pipeline-service/bin/gitlab.sh
source "$SCRIPT_DIR/gitlab.sh"

usage() {
  printf "
Usage:
    %s [options]

Fetch the latest commit from Pipeline Service Github repo
and update the image tags in the Gitlab repo where the config lives.

Optional arguments:
    --automerge
        Automatically merge the change.
    -scm, --source-control-management SCM
        Source Code Management tools like github, gitlab, bitbucket etc.
        Default: gitlab
    -d, --debug
        Activate tracing/debug mode.
    -h, --help
        Display this message.

Example:
    %s -scm gitlab
" "${0##*/}" "${0##*/}" >&2
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
    --automerge)
      AUTOMERGE="true"
      ;;
    -scm | --source-code-management)
      shift
      SCM="$1"
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
  AUTOMERGE="${AUTOMERGE:-false}"
  SCM="${SCM:-gitlab}"
  TARGET_BRANCH="${TARGET_BRANCH:-main}"
}

http_retry() {
  printf "HTTP error when accessing '%s': %s\n" "$http_url" "$resp_http_code" >&2
  retry=$((retry - 1))
  if [ "$retry" = "0" ]; then
    printf "Error: \n" >&2
    cat "$http_logs" >&2
    exit 1
  else
    printf "Retrying...\n"
  fi
}

get_latest_commit() {
  printf "Fetching the latest commit\n"
  http_url="https://api.github.com/repos/openshift-pipelines/pipeline-service/commits/$TARGET_BRANCH"
  http_logs="/tmp/fetch_commit.json"
  retry=3
  while true; do
    resp_http_code=$(
      curl -sw '%{http_code}' -o "$http_logs" \
        -H "Accept: application/vnd.github.VERSION.sha" \
        "$http_url"
    )
    case $resp_http_code in
    2*)
      LATEST_COMMIT=$(cut -c -7 <"$http_logs")
      break
      ;;
    *)
      http_retry
      ;;
    esac
  done
}

main() {
  parse_args "$@"
  "${SCM}_process"
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi
