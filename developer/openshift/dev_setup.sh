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

  GIT_URL=$(yq '.git_url // "https://github.com/openshift-pipelines/pipeline-service.git"' "$CONFIG")
  GIT_REF=$(yq '.git_ref // "main"' "$CONFIG")

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

install_minio() {
  local APP="minio"

  #############################################################################
  # Install the minio operator
  #############################################################################

  echo -n "- Secret: "
  TEKTON_RESULTS_MINIO_USER="$(yq '.tekton_results_log.user // "minio"' "$CONFIG")"
  TEKTON_RESULTS_MINIO_PASSWORD="$(yq ".tekton_results_log.password // \"$(openssl rand -base64 20)\"" "$CONFIG")"
  
  COMPUTE_DIR="$WORK_DIR"/credentials/manifests/compute/tekton-results
  mkdir -p "$COMPUTE_DIR"

  minio_configuration_secret="minio-storage-configuration"
  # secret with minio tenant configuration
  results_minio_conf_secret_path="$COMPUTE_DIR/${minio_configuration_secret}.yaml"

  minio_credentials_secret="s3-credentials"
  # secret with minio credentials for tekton-results api server
  results_minio_cred_secret_path="$COMPUTE_DIR/${minio_credentials_secret}.yaml"

  export TEKTON_RESULTS_MINIO_USER
  export TEKTON_RESULTS_MINIO_PASSWORD
  minio_conf_template="$DEV_DIR/gitops/argocd/pipeline-service/tekton-results/templates/${minio_configuration_secret}.yaml"
  envsubst < "$minio_conf_template" > "$results_minio_conf_secret_path"
  # unset env variables, but save their values
  export -n TEKTON_RESULTS_MINIO_USER
  export -n TEKTON_RESULTS_MINIO_PASSWORD

  kubectl create secret generic "${minio_credentials_secret}" \
  --from-literal=S3_ACCESS_KEY_ID="$TEKTON_RESULTS_MINIO_USER" \
  --from-literal=S3_SECRET_ACCESS_KEY="$TEKTON_RESULTS_MINIO_PASSWORD" \
  -n tekton-results --dry-run=client -o yaml >> "$results_minio_cred_secret_path"

  kubectl apply -f "$PROJECT_DIR/operator/gitops/argocd/pipeline-service/tekton-results/base/namespace.yaml" >/dev/null
  kubectl apply -f "$results_minio_conf_secret_path" >/dev/null
  kubectl apply -f "$results_minio_cred_secret_path" >/dev/null
  echo "OK"

  echo -n "- Installing minio: "
  kubectl apply -f "$DEV_DIR/gitops/argocd/$APP/application.yaml" >/dev/null
  echo "OK"

  # Subscription information for potential debug
  mkdir -p "$WORK_DIR/logs/$APP"

  echo "- Checking deployment status:"
  check_deployments "openshift-operators" "minio-operator" | indent 2
  check_pod_by_label "tekton-results" "app=minio" | indent 2 
}

setup_compute_access() {
  if [ -n "${USE_CURRENT_BRANCH:-}" ]; then
    kustomization_dir="$PROJECT_DIR/operator/gitops/compute/pipeline-service-manager"
  else
    kustomization_dir="$GIT_URL/operator/gitops/compute/pipeline-service-manager?ref=$GIT_REF"
  fi
  "$PROJECT_DIR/operator/images/access-setup/content/bin/setup_compute.sh" \
    ${DEBUG:+"$DEBUG"} \
    --kubeconfig "$KUBECONFIG" \
    --work-dir "$WORK_DIR" \
    --kustomization "$kustomization_dir" |
    indent 2
}

install_pipeline_service() {

  TEKTON_RESULTS_DATABASE_USER="$(yq '.tekton_results_db.user' "$CONFIG")"
  TEKTON_RESULTS_DATABASE_PASSWORD="$(yq '.tekton_results_db.password' "$CONFIG")"
  export TEKTON_RESULTS_DATABASE_USER
  export TEKTON_RESULTS_DATABASE_PASSWORD

  echo "- Setup working directory:"
  "$PROJECT_DIR/operator/images/access-setup/content/bin/setup_work_dir.sh" \
    ${DEBUG:+"$DEBUG"} \
    --work-dir "$WORK_DIR" \
    --kustomization "git::$GIT_URL/developer/openshift/gitops/argocd?ref=$GIT_REF" |
    indent 2

  if [ -n "${USE_CURRENT_BRANCH:-}" ]; then
    manifest_dir="$(find "$WORK_DIR/environment/compute" -mindepth 1 -maxdepth 1 -type d)"
    repo_url="$(git remote get-url origin | sed "s|git@github.com:|https://github.com/|")"
    branch="$(git branch --show-current)"
    # In the case of a PR, there's no branch, so use the revision instead
    branch="${branch:-$(git rev-parse HEAD)}"
    kubectl create -k "$manifest_dir" --dry-run=client -o yaml >"$manifest_dir/pipeline-service.yaml"
    yq -i ".spec.source.repoURL=\"$repo_url\" | .spec.source.targetRevision=\"$branch\"" "$manifest_dir/pipeline-service.yaml"
    yq -i '.resources[0]="pipeline-service.yaml"' "$manifest_dir/kustomization.yaml"
  fi

  echo "- Deploy applications:"
  "$PROJECT_DIR/operator/images/cluster-setup/content/bin/install.sh" \
    ${DEBUG:+"$DEBUG"} \
    --workspace-dir "$WORK_DIR" | indent 2
}

main() {
  parse_args "$@"
  precheck_binary "curl" "argocd" "kubectl" "yq"
  init
  check_cluster_role
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
