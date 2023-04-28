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

# shellcheck source=operator/images/cluster-setup/content/bin/utils.sh
source "$PROJECT_DIR/operator/images/cluster-setup/content/bin/utils.sh"

GITOPS_DIR="$PROJECT_DIR/operator/gitops"
CONFIG="$DEV_DIR/../config.yaml"

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
        exit 0
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
  # get the list of APPS to be installed
  read -ra APP_LIST <<< "$(yq eval '.apps // [] | join(" ")' "$CONFIG")"

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
  rsync --archive --delete --exclude .gitignore --exclude README.md "$GITOPS_DIR/sre/" "$WORK_DIR"

  mkdir -p "$WORK_DIR/credentials/kubeconfig/compute"
  cp "$KUBECONFIG" "$WORK_DIR/credentials/kubeconfig/compute/compute.kubeconfig.base"

  KUBECONFIG="$WORK_DIR/credentials/kubeconfig/compute/compute.kubeconfig.base"
  export KUBECONFIG
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
  echo "- Enabling HTTP2 for ingress" | indent 2
  oc annotate ingresses.config/cluster ingress.operator.openshift.io/default-enable-http2=true --overwrite=true| indent 6
}

install_openshift_gitops() {
  APP="openshift-gitops"

  local ns="$APP"

  #############################################################################
  # Install the gitops operator
  #############################################################################
  echo -n "- OpenShift-GitOps: "
  kubectl apply -k "$DEV_DIR/operators/$APP" >/dev/null
  echo "OK"

  # Subscription information for potential debug
  mkdir -p "$WORK_DIR/logs/$APP"
  kubectl get subscriptions $APP-operator -n openshift-operators -o yaml >"$WORK_DIR/logs/$APP/subscription.yaml"

  #############################################################################
  # Wait for the URL to be available
  #############################################################################
  echo -n "- Argo CD dashboard: "
  test_cmd="kubectl get route/openshift-gitops-server --ignore-not-found -n $ns -o jsonpath={.spec.host}"
  ARGOCD_HOSTNAME="$(${test_cmd})"
  until curl --fail --insecure --output /dev/null --silent "https://$ARGOCD_HOSTNAME"; do
    echo -n "."
    sleep 2
    ARGOCD_HOSTNAME="$(${test_cmd})"
  done
  echo "OK"
  echo "- Argo CD URL: https://$ARGOCD_HOSTNAME"

  #############################################################################
  # Post install
  #############################################################################
  # Log into Argo CD
  echo -n "- Argo CD Login: "
  local argocd_password
  argocd_password="$(kubectl get secret openshift-gitops-cluster -n $ns -o jsonpath="{.data.admin\.password}" | base64 --decode)"
  argocd login "$ARGOCD_HOSTNAME" --grpc-web --insecure --username admin --password "$argocd_password" >/dev/null
  echo "OK"

  # Register the host cluster as pipeline-cluster
  local cluster_name="plnsvc"
  if ! argocd cluster get "$cluster_name" >/dev/null 2>&1; then
    echo "- Register host cluster to ArgoCD as '$cluster_name': "
    argocd cluster add "$(yq e ".current-context" <"$KUBECONFIG")" --name="$cluster_name" --upsert --yes >/dev/null
    echo "  OK"
  else
    echo "- Register host cluster to ArgoCD as '$cluster_name': OK"
  fi
}

setup_compute_access() {
  kustomization_dir="$GIT_URL/operator/gitops/compute/pipeline-service-manager?ref=$GIT_REF"
  "$PROJECT_DIR/operator/images/access-setup/content/bin/setup_compute.sh" \
    ${DEBUG:+"$DEBUG"} \
    --kubeconfig "$KUBECONFIG" \
    --work-dir "$WORK_DIR" \
    --kustomization "$kustomization_dir" |
    indent 2
}

install_pipeline_service() {

  echo "- Source: ${GIT_URL//.git/}/tree/$GIT_REF"

  #############################################################################
  # Setup working directory
  #############################################################################

  TEKTON_RESULTS_DATABASE_USER="$(yq '.tekton_results_db.user' "$CONFIG")"
  TEKTON_RESULTS_DATABASE_PASSWORD="$(yq '.tekton_results_db.password' "$CONFIG")"
  export TEKTON_RESULTS_DATABASE_USER
  export TEKTON_RESULTS_DATABASE_PASSWORD
  TEKTON_RESULTS_S3_USER="$(yq '.tekton_results_s3.user // "tekton"' "$CONFIG")"
  TEKTON_RESULTS_S3_PASSWORD="$(yq ".tekton_results_s3.password // \"$(openssl rand -base64 20)\"" "$CONFIG")"
  export TEKTON_RESULTS_S3_USER
  export TEKTON_RESULTS_S3_PASSWORD

  echo "- Setup working directory:"
  "$PROJECT_DIR/operator/images/access-setup/content/bin/setup_work_dir.sh" \
    ${DEBUG:+"$DEBUG"} \
    --work-dir "$WORK_DIR" \
    --kustomization "$GIT_URL/developer/openshift/gitops/argocd?ref=$GIT_REF" |
    indent 2

  # Patch the url/branch to target the expected repository/branch
  manifest_dir="$(find "$WORK_DIR/environment/compute" -mindepth 1 -maxdepth 1 -type d)"
  for app in "pipeline-service" "pipeline-service-storage" "pipeline-service-o11y"; do
    cat << EOF >"$manifest_dir/patch-$app.yaml"
---
- op: replace
  path: "/spec/sources/0/repoURL"
  value: $GIT_URL
- op: replace
  path: "/spec/sources/0/targetRevision"
  value: $GIT_REF
EOF
    yq -i ".patches += [{\"path\": \"patch-$app.yaml\", \"target\": {\"kind\": \"Application\", \"namespace\": \"openshift-gitops\", \"name\": \"$app\" }}]" "$manifest_dir/kustomization.yaml"
  done

  #############################################################################
  # Deploy Applications
  #############################################################################

  echo "- Deploy applications:"
  "$PROJECT_DIR/operator/images/cluster-setup/content/bin/install.sh" \
    ${DEBUG:+"$DEBUG"} \
    --workspace-dir "$WORK_DIR" | indent 2
}

main() {
  parse_args "$@"
  precheck_binary "curl" "argocd" "kubectl" "yq" "oc"
  init
  check_cluster_role
  cluster_setup
  echo "[compute-access]"
  setup_compute_access
  echo
  for APP in "${APP_LIST[@]}"; do
    echo "[$APP]"
    install_"$(echo "$APP" | tr '-' '_')" | indent 2
    echo
  done
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi
