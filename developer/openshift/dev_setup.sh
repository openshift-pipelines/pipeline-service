#!/usr/bin/env bash

#quit if exit status of any cmd is a non-zero value
set -euo pipefail

DEV_DIR="$(
  cd "$(dirname "$0")" >/dev/null
  pwd
)"
PROJECT_DIR="$(
  cd "$DEV_DIR/../.." >/dev/null || exit 1
  pwd
)"

# shellcheck source=developer/openshift/utils.sh
source "$DEV_DIR/utils.sh"
KUBECONFIG=${KUBECONFIG:-$HOME/.kube/config}

usage() {
  TMPDIR=$(dirname "$(mktemp -u)")
  echo "
Usage:
    ${0##*/} [options]

Setup Pipeline Service on a single cluster.

Optional arguments:
    --force
        No question asked.
    --use-current-branch
        Use the current branch to deploy the application. In the case of a detached
        head, the revision is used instead.
    -w, --work-dir
        Directory in which to create the gitops file structure.
        If the directory already exists, all content will be removed.
        By default a temporary directory will be created in $TMPDIR.
    -d, --debug
        Activate tracing/debug mode.
    -h, --help
        Display this message.

Example:
    ${0##*/}
" >&2
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
    --force)
      FORCE=1
      ;;
    --use-current-branch)
      USE_CURRENT_BRANCH="1"
      ;;
    -w | --work-dir)
      shift
      WORK_DIR="$1"
      mkdir -p "$WORK_DIR"
      WORK_DIR="$(
        cd "$1" >/dev/null
        pwd
      )"
      ;;
    -d | --debug)
      set -x
      DEBUG="--debug"
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --)
      # End of arguments
      break
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
    esac
    shift
  done

  git fetch >/dev/null
  if [ -z "${FORCE:-}" ] && [ -n "${USE_CURRENT_BRANCH:-}" ] && ! git diff --quiet "@{upstream}"; then
    while true; do
      read -r -p "You have uncommitted/unpushed changes, do you want to continue? [y/N]: " answer
      case "$answer" in
      y | Y)
        break
        ;;
      n | N | "")
        exit 1
        ;;
      esac
    done
  fi
}

# Checks if a binary is present on the local system
precheck_binary() {
  for binary in "$@"; do
    command -v "$binary" >/dev/null 2>&1 || {
      echo "[ERROR] This script requires '$binary' to be installed on your local machine." >&2
      exit 1
    }
  done
}

init() {
  CONFIG="$DEV_DIR/../config.yaml"

  # Get the repository/branch used by ArgoCD as the source of truth
  if [ -n "${USE_CURRENT_BRANCH:-}" ]; then
    GIT_URL="$(git remote get-url origin | sed "s|git@github.com:|https://github.com/|")"
    GIT_REF="$(git branch --show-current)"
    # In the case of a PR, there's no branch, so use the revision instead
    GIT_REF="${GIT_REF:-$(git rev-parse HEAD)}"
  else
    GIT_URL=$(yq '.git_url // "https://github.com/openshift-pipelines/pipeline-service.git"' "$CONFIG")
    GIT_REF=$(yq '.git_ref // "main"' "$CONFIG")
  fi
  GIT_URL=$(echo "$GIT_URL" | sed '/\.git$/! s/$/.git/')

  # Create SRE repository folder
  WORK_DIR="${WORK_DIR:-}"
  if [[ -z "$WORK_DIR" ]]; then
    WORK_DIR=$(mktemp -d)
    echo "Working directory: $WORK_DIR"
  fi
  gitops_dir="$PROJECT_DIR/operator/gitops"
  rsync --archive --delete --exclude .gitignore --exclude README.md "$gitops_dir/sre/" "$WORK_DIR"

  mkdir -p "$WORK_DIR/credentials/kube"
  cp "$KUBECONFIG" "$WORK_DIR/credentials/kube/config"

  KUBECONFIG="$WORK_DIR/credentials/kube/config"

  export CONFIG
  export DEBUG
  export DEV_DIR
  export GIT_URL
  export GIT_REF
  export KUBECONFIG
  export PROJECT_DIR
  export WORK_DIR
}

check_cluster_role() {
  if [ "$(kubectl auth can-i '*' '*' --all-namespaces)" != "yes" ]; then
    echo
    echo "[ERROR] User '$(oc whoami)' does not have the required 'cluster-admin' role." >&2
    echo "Log into the cluster with a user with the required privileges (e.g. kubeadmin) and retry."
    exit 1
  fi
}

cluster_setup() {
  echo "[cluster-setup]"

  # By default HTTP2 is not enabled in test openshift clusters
  echo "- Enabling HTTP2 for ingress:"
  oc annotate ingresses.config/cluster \
    ingress.operator.openshift.io/default-enable-http2=true \
    --overwrite=true |
    indent 2
}

main() {
  parse_args "$@"
  precheck_binary "curl" "argocd" "kubectl" "yq" "oc"
  init
  check_cluster_role
  cluster_setup
  echo
  yq eval '.apps | .[] // []' "$CONFIG" | while read -r app; do
    echo "[$app]"
    "$PROJECT_DIR/developer/openshift/apps/$app.sh"
    echo
  done
  check_CRDs
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi
