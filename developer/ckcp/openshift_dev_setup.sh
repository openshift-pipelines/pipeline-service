#!/usr/bin/env bash

#quit if exit status of any cmd is a non-zero value
set -euo pipefail

CKCP_DIR="$(
  cd "$(dirname "$0")" >/dev/null
  pwd
)"
PROJECT_DIR="$(
  cd "$CKCP_DIR/../.." >/dev/null || exit 1
  pwd
)"

# shellcheck source=developer/ckcp/hack/util/update-git-reference.sh
source "$CKCP_DIR/hack/util/update-git-reference.sh"

# shellcheck source=operator/images/cluster-setup/bin/utils.sh
source "$PROJECT_DIR/operator/images/cluster-setup/bin/utils.sh"

GITOPS_DIR="$PROJECT_DIR/operator/gitops"
CONFIG="$CKCP_DIR/config.yaml"

KUBECONFIG=${KUBECONFIG:-$HOME/.kube/config}

usage() {
  TMPDIR=$(dirname "$(mktemp -u)")
  echo "
Usage:
    ${0##*/} [options]

Setup Pipeline Service on a cluster running on KCP.

Optional arguments:
    -w, --work-dir
        Directory in which to create the gitops file structure.
        If the directory already exists, all content will be removed.
        By default a temporary directory will be created in $TMPDIR.
    --tekton-results-database-user TEKTON_RESULTS_DATABASE_USER
        Username for tekton results database.
        Can be read from \$TEKTON_RESULTS_DATABASE_USER
        Default: %s
    --tekton-results-database-password TEKTON_RESULTS_DATABASE_PASSWORD
        Password for tekton results database.
        Can be read from \$TEKTON_RESULTS_DATABASE_PASSWORD
        Default: %s
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
    -w | --work-dir)
      shift
      WORK_DIR="$1"
      mkdir -p "$WORK_DIR"
      WORK_DIR="$(cd "$1" >/dev/null; pwd)"
      ;;
    --tekton-results-database-user)
      shift
      TEKTON_RESULTS_DATABASE_USER="$1"
      ;;
    --tekton-results-database-password)
      shift
      TEKTON_RESULTS_DATABASE_PASSWORD="$1"
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
}

# Checks if a binary is present on the local system
precheck_binary() {
  for binary in "$@"; do
    command -v "$binary" >/dev/null 2>&1 || {
      echo >&2 "openshift_dev_setup.sh requires '$binary' command-line utility to be installed on your local machine. Aborting..."
      exit 1
    }
  done
}

init() {
  APP_LIST=(
            "openshift-gitops"
            "cert-manager"
            "ckcp"
           )
  # get the list of APPS to be installed
  read -ra APPS <<< "$(yq eval '.apps | join(" ")' "$CONFIG")"
  for app in  "${APPS[@]}"
  do
    APP_LIST+=("$app")
  done

  # get cluster type
  cluster_type=$(yq '.cluster_type // "openshift"' "$CONFIG")

  GIT_URL=$(yq '.git_url // "https://github.com/openshift-pipelines/pipeline-service.git"' "$CONFIG")
  GIT_REF=$(yq '.git_ref // "main"' "$CONFIG")

  # get list of CRs to sync
  read -ra CRS_TO_SYNC <<< "$(yq eval '.crs_to_sync | join(" ")' "$CONFIG")"
  if (( "${#CRS_TO_SYNC[@]}" <= 0 )); then
    CRS_TO_SYNC=(
                "deployments.apps"
                "services"
                "ingresses.networking.k8s.io"
		"networkpolicies.networking.k8s.io"
                "pipelines.tekton.dev"
                "pipelineruns.tekton.dev"
                "tasks.tekton.dev"
		"repositories.pipelinesascode.tekton.dev"
              )
  fi

  # Create SRE repository folder
  WORK_DIR="${WORK_DIR:-}"
  if [[ -z "$WORK_DIR" ]]; then
    WORK_DIR=$(mktemp -d)
    echo "Working directory: $WORK_DIR"
  fi
  if [[ -d "$WORK_DIR" ]]; then
    rm -rf "$WORK_DIR"
  fi
  cp -rf "$GITOPS_DIR/sre" "$WORK_DIR"
  update_git_reference "$GIT_URL" "$GIT_REF" "$WORK_DIR/environment/kcp/registration/kustomization.yaml"

  for dir in kcp compute; do
    mkdir -p "$WORK_DIR/credentials/kubeconfig/$dir"
  done
  cp "$KUBECONFIG" "$WORK_DIR/credentials/kubeconfig/compute/compute.kubeconfig.base"

  KUBECONFIG_KCP="$WORK_DIR/credentials/kubeconfig/kcp/admin.kubeconfig.base"
  KUBECONFIG="$WORK_DIR/credentials/kubeconfig/compute/compute.kubeconfig.base"
  KUBECONFIG_MERGED="merged-config.kubeconfig:$KUBECONFIG:$KUBECONFIG_KCP"
  export KUBECONFIG
  kcp_org="root:default"
  kcp_workspace="pipeline-service-compute"
  kcp_version="$(yq '.version.kcp' "$CONFIG")"
}

# To ensure that dependencies are satisfied
precheck() {
  if [ "$(kubectl plugin list | grep -c 'kubectl-kcp')" -eq 0 ]; then
    printf "kcp plugin could not be found\n"
    exit 1
  fi

  kubectl_kcp_version=$(kubectl-kcp --version | cut -d '-' -f 2)
  if [ "${kubectl_kcp_version}" != "${kcp_version}" ]; then
    printf "[ERROR] kcp plugin version mismatch: expected '%s', got '%s'\n" "$kcp_version" "$kubectl_kcp_version" >&2
    printf "Please install kcp plugin with version '%s'\n" "$kcp_version"
    exit 1
  fi
}

check_cluster_role() {
  if [ "$(kubectl auth can-i '*' '*' --all-namespaces)" != "yes" ]; then
    echo
    echo "[ERROR] User '$(oc whoami)' does not have the required 'cluster-admin' role." 1>&2
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
  kubectl apply -k "$CKCP_DIR/openshift-operators/$APP" >/dev/null
  echo "OK"

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
  if ! KUBECONFIG="$KUBECONFIG_MERGED" argocd cluster get "$cluster_name" >/dev/null 2>&1; then
    echo "- Register host cluster to ArgoCD as '$cluster_name': "
    argocd cluster add "$(yq e ".current-context" <"$KUBECONFIG")" --name="$cluster_name" --upsert --yes >/dev/null
    echo "  OK"
	else
    echo "- Register host cluster to ArgoCD as '$cluster_name': OK"
	fi
}

install_cert_manager(){
  APP="cert-manager-operator"
  echo "- OpenShift-Cert-Manager: "
  kubectl apply -f "$GITOPS_DIR/argocd/argo-apps/$APP.yaml" >/dev/null
  check_deployments "openshift-cert-manager" "cert-manager" "cert-manager-cainjector" "cert-manager-webhook" | indent 2
}

install_ckcp() {
  APP="ckcp"

  local ns="$APP"

  # #############################################################################
  # # Deploy KCP
  # #############################################################################
  local ckcp_manifest_dir=$CKCP_DIR/$cluster_type
  local ckcp_dev_dir=$ckcp_manifest_dir/overlays/dev
  local ckcp_temp_dir=$ckcp_manifest_dir/overlays/temp

  # To ensure kustomization.yaml file under overlays/temp won't be changed, remove the directory overlays/temp if it exists
  if [ -d "$ckcp_temp_dir" ]; then
    rm -rf "$ckcp_temp_dir"
  fi
  cp -rf "$ckcp_dev_dir" "$ckcp_temp_dir"

  local ckcp_route
  domain_name="$(kubectl get ingresses.config/cluster -o jsonpath='{.spec.domain}')"
  ckcp_route="ckcp-ckcp.$domain_name"
  echo "
patches:
  - target:
      kind: Ingress
      name: ckcp
    patch: |-
      - op: add
        path: /spec/rules/0/host
        description: An ingress host needs to be defined which has the routing suffix of your cluster.
        value: $ckcp_route
  - target:
      kind: Deployment
      name: ckcp
    patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/env/0/value
        description: This value refers to the hostAddress defined in the Route.
        value: $ckcp_route
  - target:
      kind: Certificate
      name: kcp
    patch: |-
      - op: add
        path: /spec/dnsNames/-
        description: This value refers to the hostAddress defined in the Route.
        value: $ckcp_route " >>"$ckcp_temp_dir/kustomization.yaml"

  echo -n "- kcp $kcp_version: "
  # Deploy ckcp until all resources are successfully appied to OCP cluster 
  local i=0
  while ! error_msg=$(kubectl apply -k "$ckcp_temp_dir" 2>&1 1>/dev/null); do
    sleep 10
    i=$((i+1))
    if [ $i -gt 12 ]; then
      printf "\n Failed to deploy ckcp \n"
      exit_error "$error_msg"
    fi
  done
  # Check if ckcp pod status is Ready
  kubectl wait --for=condition=Ready -n $ns pod -l=app=kcp-in-a-pod --timeout=90s >/dev/null
  # Clean up kustomize temp dir
  rm -rf "$ckcp_temp_dir"

  #############################################################################
  # Post install
  #############################################################################
  # Copy the kubeconfig of kcp from inside the pod onto the local filesystem
  podname="$(kubectl get pods --ignore-not-found -n "$ns" -l=app=kcp-in-a-pod -o jsonpath='{.items[0].metadata.name}')"
  mkdir -p "$(dirname "$KUBECONFIG_KCP")"
  # Wait until admin.kubeconfig file is generated inside ckcp pod
  while [[ $(kubectl exec -n $ns "$podname" -- ls /etc/kcp/config/admin.kubeconfig >/dev/null 2>&1; echo $?) -ne 0 ]]; do
    echo -n "."
    sleep 5
  done
  kubectl cp "$ns/$podname:/etc/kcp/config/admin.kubeconfig" "$KUBECONFIG_KCP" >/dev/null
  echo "OK"

  # Check if external ip is assigned and replace kcp's external IP in the kubeconfig file
  echo -n "- Route: "
  if grep -q "ckcp-ckcp.apps.domain.org" "$KUBECONFIG_KCP"; then
    yq e -i "(.clusters[].cluster.server) |= sub(\"ckcp-ckcp.apps.domain.org:6443\", \"$ckcp_route:443\")" "$KUBECONFIG_KCP"
  fi
  echo "OK"

  # Workaround to prevent the creation of a new workspace until KCP is ready.
  # This fixes `error: creating a workspace under a Universal type workspace is not supported`.
  ws_name=$(echo "$kcp_org" | cut -d: -f2)
  local sec=0
  while ! KUBECONFIG="$KUBECONFIG_KCP" kubectl kcp workspace create "$ws_name" --type root:organization --ignore-existing &>/dev/null; do
    if  [ "$sec" -gt 100 ]; then
      exit 1
    fi
    sleep 5
    sec=$((sec + 5))
  done

  echo "- Setup kcp access:"
  "$PROJECT_DIR/operator/images/access-setup/content/bin/setup_kcp.sh" \
    ${DEBUG:+"$DEBUG"} \
    --kubeconfig "$KUBECONFIG_KCP" \
    --kcp-org "$kcp_org" \
    --kcp-workspace "$kcp_workspace" \
    --work-dir "$WORK_DIR" \
    --kustomization "$GIT_URL/operator/gitops/kcp/pac-manager?ref=$GIT_REF" |
    indent 2
  KUBECONFIG_KCP="$WORK_DIR/credentials/kubeconfig/kcp/ckcp-ckcp.${ws_name}.${kcp_workspace}.kubeconfig"
}

install_pipeline_service() {

  TEKTON_RESULTS_DATABASE_USER="$(yq '.tekton_results_db.user' "$CONFIG")"
  TEKTON_RESULTS_DATABASE_PASSWORD="$(yq '.tekton_results_db.password' "$CONFIG")"

  TEKTON_RESULTS_DATABASE_USER=${TEKTON_RESULTS_DATABASE_USER:="tekton"}
  TEKTON_RESULTS_DATABASE_PASSWORD=${TEKTON_RESULTS_DATABASE_PASSWORD:=$(openssl rand -base64 20)}

  echo "- Setup compute access:"
  "$PROJECT_DIR/operator/images/access-setup/content/bin/setup_compute.sh" \
    ${DEBUG:+"$DEBUG"} \
    --kubeconfig "$KUBECONFIG" \
    --work-dir "$WORK_DIR" \
    --kustomization "$GIT_URL/operator/gitops/compute/pac-manager?ref=$GIT_REF" \
    --git-remote-url "$GIT_URL" \
    --git-remote-ref "$GIT_REF" \
    --tekton-results-database-user "$TEKTON_RESULTS_DATABASE_USER" \
    --tekton-results-database-password "$TEKTON_RESULTS_DATABASE_PASSWORD" 2>&1 |
    indent 2

  echo "- Deploy compute:"
  KUBECONFIG="" "$PROJECT_DIR/operator/images/cluster-setup/bin/install.sh" \
    ${DEBUG:+"$DEBUG"} \
    --workspace-dir "$WORK_DIR" | indent 2

  echo "- Install Pipelines as Code:"
  # Passing dummy values to the parameters of the pac/setup.sh script
  # because we only want to install the runner side of resources.
  GITOPS_REPO="https://example.git.com/my/repo" GIT_TOKEN="placeholder_token" \
    WEBHOOK_SECRET="placeholder_webhook" \
    "$GITOPS_DIR/pac/setup.sh" | indent 4

  echo -n "- Install tekton-results DB: "
  kubectl apply -k "$CKCP_DIR/manifests/tekton-results-db/openshift" 2>&1 |
  indent 4

}

register_compute() {

  # Gateway config is not supported in ckcp because we don't ship yet the glbc component
  rm -rf "$WORK_DIR"/environment/kcp/gateway

  resources="$(printf '%s,' "${CRS_TO_SYNC[@]}")"
  resources=${resources%,}
  echo "- Register compute to KCP"
  "$PROJECT_DIR/operator/images/kcp-registrar/bin/register.sh" \
    ${DEBUG:+"$DEBUG"} \
    --kcp-org "root:default" \
    --kcp-workspace "$kcp_workspace" \
    --kcp-sync-tag "$kcp_version" \
    --workspace-dir "$WORK_DIR" \
    --crs-to-sync "$(IFS=,; echo "${CRS_TO_SYNC[*]}")" |
    indent 4

}

main() {
  parse_args "$@"
  precheck_binary "kubectl" "yq" "curl" "argocd"
  init
  precheck
  check_cluster_role
  for APP in "${APP_LIST[@]}"; do
    echo "[$APP]"
    install_"$(echo "$APP" | tr '-' '_')" | indent 2
    echo
  done
  echo [sync]
  register_compute
  printf "\nUse the below KUBECONFIG to get access to the kcp workspace and compute cluster respectively.\n"
  printf "KUBECONFIG_KCP: %s\n" "$KUBECONFIG_KCP"
  printf "KUBECONFIG: %s\n" "$KUBECONFIG"

  printf "\nYou can also set the following aliases to access the kcp workspace and compute cluster respectively.\n"
  printf "alias kkcp='KUBECONFIG=%s kubectl'\n" "$KUBECONFIG_KCP"
  printf "alias kcompute='KUBECONFIG=%s kubectl'\n" "$KUBECONFIG"
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi
