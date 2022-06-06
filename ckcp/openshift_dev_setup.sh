#!/usr/bin/env bash

#quit if exit status of any cmd is a non-zero value
set -euo pipefail
# set -x

SCRIPT_DIR="$(
  cd "$(dirname "$0")" >/dev/null
  pwd
)"

GITOPS_DIR="$(dirname "$SCRIPT_DIR")/gitops/argocd/argocd-apps"
CKCP_DIR="$(dirname "$SCRIPT_DIR")/ckcp"
WORK_DIR="$SCRIPT_DIR/work"
KUBECONFIG=${KUBECONFIG:-$HOME/.kube/config}
KUBECONFIG_KCP="$WORK_DIR/kubeconfig/admin.kubeconfig"
KUBECONFIG_MERGED="merged-config.kubeconfig:$KUBECONFIG:$KUBECONFIG_KCP"

usage() {
  echo "
Usage:
    ${0##*/} [options]

Setup the pipeline service on a cluster running on KCP.

Optional arguments:
    -a, --app APP
        Install APP in the cluster. APP must be in [pipelines, triggers].
        The flag can be repeated to install multiple apps.
    --all
        Install all applications.
    -d, --debug
        Activate tracing/debug mode.
    -h, --help
        Display this message.

Example:
    ${0##*/} --all
" >&2

}

parse_args() {
  local default_list="openshift-gitops ckcp"
  local pipeline_list="pipelines_crds pipelines_controller"
  local trigger_list="triggers_crds triggers_interceptors triggers_controller"
  APP_LIST="$default_list"
  cluster_type="openshift"

  while [[ $# -gt 0 ]]; do
    case $1 in
    -a | --app)
      shift
      case $1 in
      pipelines)
        APP_LIST="$APP_LIST $pipeline_list"
        ;;
      triggers)
        APP_LIST="$APP_LIST $trigger_list"
        ;;
      *)
        echo "[ERROR] Unsupported app: $1" >&2
        usage
        exit 1
        ;;
      esac
      ;;
    --all)
      APP_LIST="$default_list $pipeline_list $trigger_list"
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

check_cluster_role() {
  if [ "$(kubectl auth can-i '*' '*' --all-namespaces)" != "yes" ]; then
    echo
    echo "[ERROR] User '$(oc whoami)' does not have the required 'cluster-admin' role." 1>&2
    echo "Log into the cluster with a user with the required privileges (e.g. kubeadmin) and retry."
    exit 1
  fi
}

install_app() {
  APP="$1"

  echo -n "  - $APP application: "
  kubectl apply -f "$GITOPS_DIR/$APP.yaml" --wait >/dev/null
  argocd app wait "$APP" >/dev/null
  echo "OK"
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
  local APP="cert-manager"
  # #############################################################################
  # # Install the cert manager operator
  # #############################################################################
  echo -n "  - openshift-cert-manager-operator: "
  kubectl apply -f "$CKCP_DIR/argocd-apps/$APP.yaml" >/dev/null 2>&1
  argocd app wait "$APP" >/dev/null 2>&1
  # Check cert manager pods until they are ready
  while [ "$(kubectl -n openshift-cert-manager get pods --field-selector=status.phase=Running 2>/dev/null | grep -c cert-manager)" != 3 ]
  do
    echo -n "."
    sleep 5
  done
  echo "OK"
}

install_ckcp() {
  APP="ckcp"

  local ns="$APP"
  local kube_dir="$WORK_DIR/kubeconfig"

  # Install cert manager operator
  install_cert_manager

  # #############################################################################
  # # Deploy KCP
  # #############################################################################
  local ckcp_manifest_dir=$CKCP_DIR/$cluster_type
  local ckcp_dev_dir=$ckcp_manifest_dir/overlays/dev
  local ckcp_temp_dir=$ckcp_manifest_dir/overlays/temp

  # To ensure kustomization.yaml file under overlays/temp won't be changed, remove the dirctory overlays/temp if it exists
  if [ -d "$ckcp_temp_dir" ]; then
    rm -rf $ckcp_temp_dir
  fi
  cp -rf $ckcp_dev_dir $ckcp_temp_dir

  local ckcp_route
  domain_name="$(kubectl get ingresses.config/cluster -o jsonpath='{.spec.domain}')"
  ckcp_route="$(echo ckcp-ckcp.$domain_name)"
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
        value: $ckcp_route " >> $ckcp_temp_dir/kustomization.yaml

  echo -n "  - kcp: "
  kubectl apply -k $ckcp_temp_dir >/dev/null 2>&1
  # Check if ckcp pod status is Ready
  while [[ $(kubectl -n $ns  get pods -l=app=kcp-in-a-pod -o 'jsonpath={.items[0].status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do 
    echo -n "."
    sleep 5
  done
  echo "OK"

  rm -rf $ckcp_temp_dir

  #############################################################################
  # Post install
  #############################################################################
  # Copy the kubeconfig of kcp from inside the pod onto the local filesystem
  podname="$(kubectl get pods --ignore-not-found -n "$ns" -l=app=kcp-in-a-pod -o jsonpath='{.items[0].metadata.name}')"
  mkdir -p "$(dirname "$KUBECONFIG_KCP")"
  kubectl cp "$APP/$podname:etc/kcp/config/admin.kubeconfig" "$KUBECONFIG_KCP" >/dev/null

  # Check if external ip is assigned and replace kcp's external IP in the kubeconfig file
  echo -n "  - Route: "
  if grep -q "ckcp-ckcp.apps.domain.org" "$KUBECONFIG_KCP"; then
    yq e -i "(.clusters[].cluster.server) |= sub(\"ckcp-ckcp.apps.domain.org:6443\", \"$ckcp_route:443\")" "$KUBECONFIG_KCP"
  fi
  echo "OK"

  # Register the host cluster to KCP
  echo -n "  - Workspace: "
  # It's not allowed to create WorkloadCluster resource in a non-universal workspace
  if ! KUBECONFIG="$KUBECONFIG_KCP" kubectl get workspaces demo >/dev/null 2>&1; then
    KUBECONFIG="$KUBECONFIG_KCP" kubectl kcp workspaces create demo --enter &>/dev/null
  fi
  echo "OK"

  echo -n "  - Workloadcluster pipeline-cluster registration: "
  if ! KUBECONFIG="$KUBECONFIG_KCP" kubectl get WorkloadCluster local >/dev/null 2>&1; then
    (
      KUBECONFIG="$KUBECONFIG_KCP" kubectl kcp workload sync local  --syncer-image ghcr.io/kcp-dev/kcp/syncer:release-0.4  > "$kube_dir/syncer.yaml"
      kubectl apply -f "$kube_dir/syncer.yaml" >/dev/null 2>&1
      rm -rf "$kube_dir/syncer.yaml"
    )
  fi
  echo "OK"

  # Register the KCP cluster into ArgoCD
  echo -n "  - KCP cluster registration to ArgoCD: "
  if ! KUBECONFIG="$KUBECONFIG_MERGED" argocd cluster get kcp >/dev/null 2>&1; then
    KUBECONFIG="$KUBECONFIG_MERGED" argocd cluster add "workspace.kcp.dev/current" --name=kcp  --system-namespace default --yes >/dev/null 2>&1
  fi
  echo "OK"
}

install_pipelines_crds() {
  install_app pipelines-crds
}

install_pipelines_controller() {
  # Create kcp-kubeconfig secret for pipelines controller
  echo -n "  - Register KCP secret to host cluster: "
  kubectl create namespace pipelines --dry-run=client -o yaml | kubectl apply -f - --wait &>/dev/null
  kubectl create secret generic kcp-kubeconfig -n pipelines --from-file "$KUBECONFIG_KCP" --dry-run=client -o yaml | kubectl apply -f - --wait &>/dev/null 2>&1
  echo "OK"

  install_app pipelines-controller
}

install_triggers_crds() {
  install_app triggers-crds
}

install_triggers_interceptors() {
  # Create kcp-kubeconfig secrets for event listener and interceptors so that they can talk to KCP
  kubectl create secret generic kcp-kubeconfig --from-file "$KUBECONFIG_KCP" --dry-run=client -o yaml | KUBECONFIG="$KUBECONFIG_KCP" kubectl apply -f - --wait &>/dev/null
  kubectl create secret generic kcp-kubeconfig -n tekton-pipelines --from-file "$KUBECONFIG_KCP" --dry-run=client -o yaml | KUBECONFIG="$KUBECONFIG_KCP" kubectl apply -f - --wait &>/dev/null

  install_app triggers-interceptors
}

install_triggers_controller() {
  # Create kcp-kubeconfig secret for triggers controller
  kubectl create namespace triggers -o yaml --dry-run=client | kubectl apply -f - --wait &>/dev/null
  kubectl create secret generic kcp-kubeconfig -n triggers --from-file "$KUBECONFIG_KCP" --dry-run=client -o yaml | kubectl apply -f - --wait &>/dev/null

  install_app triggers-controller
}

main() {
  parse_args "$@"

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
