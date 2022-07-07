#!/usr/bin/env bash

#quit if exit status of any cmd is a non-zero value
set -euo pipefail

SCRIPT_DIR="$(
  cd "$(dirname "$0")" >/dev/null
  pwd
)"

GITOPS_DIR="$(dirname "$SCRIPT_DIR")/gitops"
CKCP_DIR="$(dirname "$SCRIPT_DIR")/ckcp"
WORK_DIR="$SCRIPT_DIR/work"
KUBECONFIG=${KUBECONFIG:-$HOME/.kube/config}
KUBECONFIG_KCP="$WORK_DIR/credentials/kubeconfig/kcp/admin.kubeconfig.base"
CR_TO_SYNC=(
            conditions.tekton.dev
            pipelines.tekton.dev
            pipelineruns.tekton.dev
            pipelineresources.tekton.dev
            runs.tekton.dev
            tasks.tekton.dev
          )

usage() {
  echo "
Usage:
    ${0##*/} [options]

Setup the pipeline service on a cluster running on KCP.

Optional arguments:
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

init(){
  APP_LIST="openshift-gitops ckcp compute"
  cluster_type="openshift"

  # Create SRE repository folder
  if [[ -d "$WORK_DIR" ]]; then
    rm -rf "$WORK_DIR"
  fi
  cp -rf "$GITOPS_DIR/sre" "$WORK_DIR"
  for dir in kcp compute; do
    mkdir -p "$WORK_DIR/credentials/kubeconfig/$dir"
  done
  cp "$KUBECONFIG" "$WORK_DIR/credentials/kubeconfig/compute/compute.kubeconfig.base"

  KUBECONFIG="$WORK_DIR/credentials/kubeconfig/compute/compute.kubeconfig.base"
  KUBECONFIG_MERGED="merged-config.kubeconfig:$KUBECONFIG:$KUBECONFIG_KCP"
  export KUBECONFIG
  kcp_workspace="compute"
  kcp_version="$(yq '.images[] | select(.name == "kcp") | .newTag' "$SCRIPT_DIR/openshift/overlays/dev/kustomization.yaml")"
}

# To ensure that dependencies are satisfied
precheck() {
  if [ "$(kubectl plugin list | grep -c 'kubectl-kcp')" -eq 0 ]  ; then
    printf "kcp plugin could not be found\n"
    exit 1
  fi

  if [ "$(kubectl plugin list | grep -c 'kubectl-cert_manager')" -eq 0 ]; then
    printf "cert_manager plugin could not be found\n"
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

  local ns="openshift-operators"

  #############################################################################
  # Install the gitops operator
  #############################################################################
  echo -n "  - OpenShift-GitOps: "
  kubectl apply -k "$CKCP_DIR/openshift-operators/$APP" >/dev/null 2>&1
  echo "OK"

  #############################################################################
  # Wait for the URL to be available
  #############################################################################
  echo -n "  - ArgoCD dashboard: "
  test_cmd="kubectl get route/openshift-gitops-server --ignore-not-found -n $APP -o jsonpath={.spec.host}"
  ARGOCD_HOSTNAME="$(${test_cmd})"
  until curl --fail --insecure --output /dev/null --silent "https://$ARGOCD_HOSTNAME"; do
    echo -n "."
    sleep 2
    ARGOCD_HOSTNAME="$(${test_cmd})"
  done
  echo "OK"
  echo "  - ArgoCD URL: https://$ARGOCD_HOSTNAME"

  #############################################################################
  # Post install
  #############################################################################
  # Log into ArgoCD
  echo -n "  - ArgoCD Login: "
  local argocd_password
  argocd_password="$(kubectl get secret openshift-gitops-cluster -n openshift-gitops -o jsonpath="{.data.admin\.password}" | base64 --decode)"
  argocd login "$ARGOCD_HOSTNAME" --grpc-web --insecure --username admin --password "$argocd_password" >/dev/null 2>&1
  echo "OK"

  # Register the host cluster as pipeline-cluster
  local cluster_name="plnsvc"
  echo -n "  - Register host cluster to ArgoCD as '$cluster_name': "
  if ! KUBECONFIG="$KUBECONFIG_MERGED" argocd cluster get "$cluster_name" >/dev/null 2>&1; then
    argocd cluster add "$(yq e ".current-context" "$KUBECONFIG")" --name="$cluster_name" --upsert --yes >/dev/null 2>&1
  fi
  echo "OK"
}

install_cert_manager() {
  local APP="cert-manager-operator"
  # #############################################################################
  # # Install the cert manager operator
  # #############################################################################
  echo -n "  - openshift-cert-manager-operator: "
  if [ "$(kubectl cert-manager check api 2>&1 | grep -c "Not ready")" -eq 1 ]; then
    kubectl apply -f "$CKCP_DIR/argocd-apps/$APP.yaml" >/dev/null 2>&1
    argocd app wait "$APP" >/dev/null 2>&1
    # Wait until cert manager is ready
    kubectl cert-manager check api --wait=5m  >/dev/null 2>&1
  fi
  echo "OK"
}

install_ckcp() {
  # Install cert manager operator
  install_cert_manager

  APP="ckcp"

  local ns="$APP"

  # #############################################################################
  # # Deploy KCP
  # #############################################################################
  local ckcp_manifest_dir=$CKCP_DIR/$cluster_type
  local ckcp_dev_dir=$ckcp_manifest_dir/overlays/dev
  local ckcp_temp_dir=$ckcp_manifest_dir/overlays/temp

  # To ensure kustomization.yaml file under overlays/temp won't be changed, remove the dirctory overlays/temp if it exists
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
        value: $ckcp_route " >> "$ckcp_temp_dir/kustomization.yaml"

  echo -n "  - kcp $kcp_version: "
  kubectl apply -k "$ckcp_temp_dir" >/dev/null 2>&1
  # Check if ckcp pod status is Ready
  kubectl wait --for=condition=Ready -n $ns pod -l=app=kcp-in-a-pod --timeout=90s >/dev/null 2>&1
  # Clean up kustomize temp dir
  rm -rf "$ckcp_temp_dir"

  #############################################################################
  # Post install
  #############################################################################
  # Copy the kubeconfig of kcp from inside the pod onto the local filesystem
  podname="$(kubectl get pods --ignore-not-found -n "$ns" -l=app=kcp-in-a-pod -o jsonpath='{.items[0].metadata.name}')"
  mkdir -p "$(dirname "$KUBECONFIG_KCP")"
  # Wait until admin.kubeconfig file is generated inside ckcp pod
  while [[ $(kubectl exec -n $APP "$podname" -- ls /etc/kcp/config/admin.kubeconfig >/dev/null 2>&1; echo $?) -ne 0 ]];do
    echo -n "."
    sleep 5
  done
  kubectl cp "$APP/$podname:/etc/kcp/config/admin.kubeconfig" "$KUBECONFIG_KCP" >/dev/null 2>&1
  KUBECONFIG="$KUBECONFIG_KCP" kubectl config rename-context "default" "workspace.kcp.dev/current" >/dev/null
  echo "OK"

  # Check if external ip is assigned and replace kcp's external IP in the kubeconfig file
  echo -n "  - Route: "
  if grep -q "ckcp-ckcp.apps.domain.org" "$KUBECONFIG_KCP"; then
    yq e -i "(.clusters[].cluster.server) |= sub(\"ckcp-ckcp.apps.domain.org:6443\", \"$ckcp_route:443\")" "$KUBECONFIG_KCP"
  fi
  echo "OK"

  # Workaround to prevent the creation of the creation of a new workspace until KCP is ready.
  # This fixes `error: creating a workspace under a Universal type workspace is not supported`.
  while ! KUBECONFIG="$KUBECONFIG_KCP" kubectl kcp workspace create "dummy" --ignore-existing >/dev/null; do
    sleep 5
  done

  echo "  - Setup kcp access:"
  "$SCRIPT_DIR/../images/access-setup/content/bin/setup_kcp.sh" \
    --kubeconfig "$KUBECONFIG_KCP" \
    --kcp-workspace "$kcp_workspace" \
    --work-dir "$WORK_DIR"
  KUBECONFIG_KCP="$WORK_DIR/credentials/kubeconfig/kcp/ckcp-ckcp.default.compute.kubeconfig"
}

install_compute(){
  echo "  - Setup compute access:"
  "$SCRIPT_DIR/../images/access-setup/content/bin/setup_compute.sh" \
    --kubeconfig "$KUBECONFIG" \
    --work-dir "$WORK_DIR"

  echo "  - Deploy compute:"
  "$SCRIPT_DIR/../images/cluster-setup/install.sh" --workspace-dir "$WORK_DIR"

  echo "  - Install Pipelines as Code:"
  # Passing dummy values to the parameters of the pac/setup.sh script
  # because we only want to install the runner side of resources.
  GITOPS_REPO="https://example.git.com/my/repo" GIT_TOKEN="placeholder_token" \
    WEBHOOK_SECRET="placeholder_webhook" \
    "$GITOPS_DIR/pac/setup.sh"

  echo "  - Register compute to KCP"
  KCP_ORG="root:default" KCP_WORKSPACE="$kcp_workspace" DATA_DIR="$WORK_DIR" KCP_SYNC_TAG="$kcp_version" \
    "$SCRIPT_DIR/../images/kcp-registrar/register.sh"

  check_cr_sync
}

check_cr_sync() {
  # Wait until CRDs are synced to KCP
  echo -n "  - Sync CRDs to KCP: "
  local cr_regexp
  cr_regexp="$(IFS=\|; echo "${CR_TO_SYNC[*]}")"
  local  wait_period=0
  while [[ "$(KUBECONFIG="$KUBECONFIG_KCP" kubectl api-resources -o name  2>&1 | grep -Ewc "$cr_regexp")" -ne ${#CR_TO_SYNC[@]} ]]
  do
    wait_period=$((wait_period+10))
    #when timeout, print out the CR resoures that is not synced to KCP
    if [ $wait_period -gt 300 ];then
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
  init
  precheck
  check_cluster_role
  for APP in $APP_LIST; do
    echo "[$APP]"
    install_"$(echo "$APP" | tr '-' '_')"
    echo
  done
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi
