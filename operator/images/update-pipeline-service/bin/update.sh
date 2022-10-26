#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

declare -r TARGET_BRANCH="main"
declare -r gitlab_ci="./.gitlab-ci.yml"

SCRIPT_DIR="$(
  cd "$(dirname "$0")" >/dev/null
  pwd
)"

# shellcheck source=operator/images/update-pipeline-service/bin/gitlab_open_mr.sh
source "$SCRIPT_DIR/gitlab_open_mr.sh"

usage() {

  printf "
Usage:
    %s [options]

Fetch the latest commit from Pipeline Service Github repo
and update the image tags in the Gitlab repo where the config lives.

Optional arguments:
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
  SCM="gitlab"
  while [[ $# -gt 0 ]]; do
    case $1 in
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
}

fetch_commits() {
  for i in {1..3}; do
    latest_commit_status=$(
      curl -sw '%{http_code}' -o /tmp/latest_commit.json \
      -H "Accept: application/vnd.github.VERSION.sha" \
      "https://api.github.com/repos/openshift-pipelines/pipeline-service/commits/$TARGET_BRANCH"
    )
    if [[ "$latest_commit_status" == "200" ]]; then
      latest_commit=$(cut -c -7 < /tmp/latest_commit.json)
    else
      if [[ "$i" -lt 3 ]]; then
        printf "Unable to fetch the latest commit. Retrying...\n"
        sleep 20
      else
        printf "Error while fetching the latest commit from GitHub. Status code: %s\n" "${latest_commit_status}" >&2
        exit 1
      fi
    fi
  done
  current_commit=$(yq '.deploy-job.image.name' < "$gitlab_ci" | cut -d ':' -f2)
}

main() {
  parse_args "$@"
  fetch_commits
  if [[ $SCM == "gitlab" ]]; then
    raise_mr_gitlab "$current_commit" "$latest_commit"
  fi
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi