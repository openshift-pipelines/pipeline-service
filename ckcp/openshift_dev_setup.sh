#!/usr/bin/env bash

#quit if exit status of any cmd is a non-zero value
set -euo pipefail

SCRIPT_DIR="$(
  cd "$(dirname "$0")" >/dev/null
  pwd
)"

# shellcheck source=ckcp/hack/util/update-git-reference.sh
source "$SCRIPT_DIR/hack/util/update-git-reference.sh"

# shellcheck source=images/cluster-setup/bin/utils.sh
source "$SCRIPT_DIR/../images/cluster-setup/bin/utils.sh"

GITOPS_DIR="$(dirname "$SCRIPT_DIR")/gitops"
CKCP_DIR="$(dirname "$SCRIPT_DIR")/ckcp"
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
    -d | --debug)
      set -x
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
  read -ra APPS <<< "$(yq eval '.APPS | join(" ")' "$CONFIG")"
  for app in  "${APPS[@]}"
  do
    APP_LIST+=("$app")
  done

  # get cluster type
  cluster_type=$(yq '.CLUSTER_TYPE // "openshift"' "$CONFIG")

  GIT_URL=$(yq '.GIT_URL // "https://github.com/openshift-pipelines/pipeline-service.git"' "$CONFIG")
  GIT_REF=$(yq '.GIT_REF // "main"' "$CONFIG")

  # get list of CRs to sync
  read -ra CR_TO_SYNC <<< "$(yq eval '.CR_TO_SYNC | join(" ")' "$CONFIG")"
  if (( "${#CR_TO_SYNC[@]}" <= 0 )); then
    CR_TO_SYNC=(
                "deployments.apps"
                "services"
                "ingresses.networking.k8s.io"
                "pipelines.tekton.dev"
                "pipelineruns.tekton.dev"
                "runs.tekton.dev"
                "tasks.tekton.dev"
                "networkpolicies.networking.k8s.io"
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
  update_git_reference "$GIT_URL" "$GIT_REF" "$WORK_DIR/environment/kcp/kustomization.yaml"

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
  kcp_version="$(yq '.images[] | select(.name == "kcp") | .newTag' "$SCRIPT_DIR/openshift/overlays/dev/kustomization.yaml")"
}

# To ensure that dependencies are satisfied
precheck() {
  if [ "$(kubectl plugin list | grep -c 'kubectl-kcp')" -eq 0 ]; then
    printf "kcp plugin could not be found\n"
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
  echo -n "  - OpenShift-GitOps: "
  kubectl apply -k "$CKCP_DIR/openshift-operators/$APP" >/dev/null
  echo "OK"

  #############################################################################
  # Wait for the URL to be available
  #############################################################################
  echo -n "  - Argo CD dashboard: "
  test_cmd="kubectl get route/openshift-gitops-server --ignore-not-found -n $ns -o jsonpath={.spec.host}"
  ARGOCD_HOSTNAME="$(${test_cmd})"
  until curl --fail --insecure --output /dev/null --silent "https://$ARGOCD_HOSTNAME"; do
    echo -n "."
    sleep 2
    ARGOCD_HOSTNAME="$(${test_cmd})"
  done
  echo "OK"
  echo "  - Argo CD URL: https://$ARGOCD_HOSTNAME"

  #############################################################################
  # Post install
  #############################################################################
  # Log into Argo CD
  echo -n "  - Argo CD Login: "
  local argocd_password
  argocd_password="$(kubectl get secret openshift-gitops-cluster -n $ns -o jsonpath="{.data.admin\.password}" | base64 --decode)"
  argocd login "$ARGOCD_HOSTNAME" --grpc-web --insecure --username admin --password "$argocd_password" >/dev/null
  echo "OK"

  # Register the host cluster as pipeline-cluster
  local cluster_name="plnsvc"
  echo "  - Register host cluster to ArgoCD as '$cluster_name': "
  if ! KUBECONFIG="$KUBECONFIG_MERGED" argocd cluster get "$cluster_name" >/dev/null 2>&1; then
    argocd cluster add "$(yq e ".current-context" <"$KUBECONFIG")" --name="$cluster_name" --upsert --yes >/dev/null
  fi
  echo "    OK"
}

install_cert_manager(){
  APP="cert-manager-operator"
  echo "  - OpenShift-Cert-Manager: "
  kubectl apply -f "$GITOPS_DIR/argocd/argo-apps/$APP.yaml" >/dev/null
  check_cert_manager
}

check_cert_manager() {
  certManagerDeployments=("cert-manager" "cert-manager-cainjector" "cert-manager-webhook")
  check_deployments "openshift-cert-manager" "${certManagerDeployments[@]}"
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

  echo -n "  - kcp $kcp_version: "
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
  echo -n "  - Route: "
  if grep -q "ckcp-ckcp.apps.domain.org" "$KUBECONFIG_KCP"; then
    yq e -i "(.clusters[].cluster.server) |= sub(\"ckcp-ckcp.apps.domain.org:6443\", \"$ckcp_route:443\")" "$KUBECONFIG_KCP"
  fi
  echo "OK"

  # Workaround to prevent the creation of a new workspace until KCP is ready.
  # This fixes `error: creating a workspace under a Universal type workspace is not supported`.
  ws_name=$(echo "$kcp_org" | cut -d: -f2)
  while ! KUBECONFIG="$KUBECONFIG_KCP" kubectl kcp workspace create "$ws_name" --type root:organization --ignore-existing >/dev/null; do
    sleep 5
  done
  KUBECONFIG="$KUBECONFIG_KCP" kubectl kcp workspace use "$ws_name"

  echo "  - Setup kcp access:"
  "$SCRIPT_DIR/../images/access-setup/content/bin/setup_kcp.sh" \
    --kubeconfig "$KUBECONFIG_KCP" \
    --kcp-org "$kcp_org" \
    --kcp-workspace "$kcp_workspace" \
    --work-dir "$WORK_DIR" \
    --kustomization "$GIT_URL/gitops/kcp/pac-manager?ref=$GIT_REF"
  KUBECONFIG_KCP="$WORK_DIR/credentials/kubeconfig/kcp/ckcp-ckcp.${ws_name}.${kcp_workspace}.kubeconfig"
}

install_pipeline_service() {
  echo "  - Setup compute access:"
  "$SCRIPT_DIR/../images/access-setup/content/bin/setup_compute.sh" \
    --kubeconfig "$KUBECONFIG" \
    --work-dir "$WORK_DIR" \
    --kustomization "$GIT_URL/gitops/compute/pac-manager?ref=$GIT_REF" \
    --git-remote-url "$GIT_URL" \
    --git-remote-ref "$GIT_REF"

  echo "  - Deploy compute:"
  "$SCRIPT_DIR/../images/cluster-setup/bin/install.sh" --workspace-dir "$WORK_DIR"

  echo "  - Install Pipelines as Code:"
  # Passing dummy values to the parameters of the pac/setup.sh script
  # because we only want to install the runner side of resources.
  GITOPS_REPO="https://example.git.com/my/repo" GIT_TOKEN="placeholder_token" \
    WEBHOOK_SECRET="placeholder_webhook" \
    "$GITOPS_DIR/pac/setup.sh"

}

register_compute() {
  echo "  - Register compute to KCP"
  "$(dirname "$SCRIPT_DIR")/images/kcp-registrar/register.sh" \
    --kcp-org "root:default" \
    --kcp-workspace "$kcp_workspace" \
    --kcp-sync-tag "$kcp_version" \
    --workspace-dir "$WORK_DIR"

  check_cr_sync
}

check_cr_sync() {
  # Wait until CRDs are synced to KCP
  echo -n "  - Sync CRDs to KCP: "
  local cr_regexp
  cr_regexp="$(
    IFS=\|
    echo "${CR_TO_SYNC[*]}"
  )"
  local wait_period=0
  while [[ "$(KUBECONFIG="$KUBECONFIG_KCP" kubectl api-resources -o name 2>&1 | grep -Ewc "$cr_regexp")" -ne ${#CR_TO_SYNC[@]} ]]; do
    wait_period=$((wait_period + 10))
    #when timeout, print out the CR resoures that is not synced to KCP
    if [ $wait_period -gt 300 ]; then
      echo "Failed to sync following resources to KCP: "
      cr_synced=$(KUBECONFIG="$KUBECONFIG_KCP" kubectl api-resources -o name)
      for cr in "${CR_TO_SYNC[@]}"; do
        if [ "$(echo "$cr_synced" | grep -wc "$cr")" -eq 0 ]; then
          echo "    * $cr"
        fi
      done
      exit 1
    fi
    echo -n "."
    sleep 10
  done
  echo "OK"
}

main() {
  parse_args "$@"
  precheck_binary "kubectl" "yq" "curl" "argocd"
  init
  precheck
  check_cluster_role
  for APP in "${APP_LIST[@]}"; do
    echo "[$APP]"
    install_"$(echo "$APP" | tr '-' '_')"
    echo
  done
  register_compute
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi
