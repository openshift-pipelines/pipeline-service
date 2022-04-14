#!/usr/bin/env bash

#quit if exit status of any cmd is a non-zero value
set -euo pipefail

SCRIPT_DIR="$(
  cd "$(dirname "$0")" >/dev/null
  pwd
)"
source "$SCRIPT_DIR/../kcp/deploy.sh"

GITOPS_DIR="$(dirname "$SCRIPT_DIR")/gitops"
WORK_DIR="$SCRIPT_DIR/work"
KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
KUBECONFIG_DIR="$WORK_DIR/kubeconfig"
KUBECONFIG_KCP="$KUBECONFIG_DIR/kcp.yaml"
KUBECONFIG_PLNSVC="$KUBECONFIG_DIR/plnsvc.clusteradmin.yaml"
mkdir -p "$KUBECONFIG_DIR"

usage() {
  echo "
Usage:
    ${0##*/} [options]

Setup the pipeline service on a cluster running on KCP.

Optional arguments:
    -p, --pipeline-cluster-kubeconfig
        Path to the kubeconfig file to the pipeline-cluster.
        Default: \"$KUBECONFIG\"
    -d, --debug
        Activate tracing/debug mode.
    -h, --help
        Display this message.

Example:
    ${0##*/} -p ~/.kube/local-cluster.config
" >&2

}

parse_args() {
  local args
  args="$(getopt -o dhp: -l "debug,help,pipeline-cluster-kubeconfig" -n "$0" -- "$@")"
  eval set -- "$args"
  while true; do
    case $1 in
    -p | --pipeline-cluster-kubeconfig)
      shift
      KUBECONFIG="$1"
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

init() {
  mkdir -p "$KUBECONFIG_DIR"
  cp "$KUBECONFIG" "$KUBECONFIG_PLNSVC"
  check_cluster_role
}

check_cluster_role() {
  if [ "$(plnsvc_config kubectl auth can-i '*' '*' --all-namespaces)" != "yes" ]; then
    echo
    echo "[ERROR] User '$(plnsvc_config oc whoami)' does not have the required 'cluster-admin' role." 1>&2
    echo "Log into the cluster with a user with the required privileges (e.g. kubeadmin) and retry."
    exit 1
  fi
}

install_ckcp() {
  APP="ckcp"

  local ns="$APP"
  local manifests_dir="$WORK_DIR/manifests"
  local podname=""
  local route
  mkdir -p "$manifests_dir"

  #############################################################################
  # Deploy KCP
  #############################################################################
  echo -n "  - KCP container: "
  plnsvc_config kubectl apply -f "$SCRIPT_DIR/manifests/$APP.yaml" >/dev/null
  echo "OK"

  #############################################################################
  # Post install
  #############################################################################
  # Copy the kubeconfig of kcp from inside the pod onto the local filesystem
  rm -f "$KUBECONFIG_KCP"
  podname="$(plnsvc_config kubectl get pods --ignore-not-found -n "$ns" -l=app=kcp-in-a-pod -o jsonpath={.items[0].metadata.name})"
  plnsvc_config kubectl wait --for jsonpath='{.status.phase}'=Running -n $APP --timeout=5m "pod/$podname"  >/dev/null
  # The file can take a moment to be properly initialized
  until tail -1 "$KUBECONFIG_KCP" 2>/dev/null | grep -q "^  *token: "; do
    plnsvc_config kubectl cp -n $APP "$podname:/tmp/workspace/.kcp/admin.kubeconfig" "$KUBECONFIG_KCP" >/dev/null
  done

  # Check if external ip is assigned and replace kcp's external IP in the kubeconfig file
  echo -n "  - Route: "
  if grep -q "//[0-9.]\+:6443" "$KUBECONFIG_KCP"; then
    route="$(plnsvc_config kubectl get route ckcp -n "$APP" -o jsonpath='{.spec.host}')"
    sed -i -e "s%//[0-9.]\+:6443%//$route:443%g" "$KUBECONFIG_KCP"
  fi
  echo "OK"

  # Make sure access to kcp-in-a-pod is good
  echo -n "  - KCP api-server: "
  kcp_config kubectl config set-cluster root:default --insecure-skip-tls-verify=true >/dev/null
  until kcp_config kubectl api-resources >/dev/null 2>&1; do
    echo -n "."
    sleep 2
  done
  echo "OK"

  echo -n "  - Switch to '$KCP_WORKSPACE' workspace: "
  while ! kcp_config kubectl kcp workspace use "$KCP_WORKSPACE" >/dev/null; do
    kcp_config kubectl kcp workspace create "$KCP_WORKSPACE" >/dev/null
  done
  sed -i -e "s%//[0-9.]\+:6443%//$route:443%g" "$KUBECONFIG_KCP"
  echo "OK"
}

install_openshift_gitops() {
  APP="openshift-gitops"

  local ns="openshift-operators"

  #############################################################################
  # Install the gitops operator
  #############################################################################
  echo -n "  - OpenShift-GitOps: "
  plnsvc_config kubectl apply -f "$GITOPS_DIR/$APP.yaml" --wait >/dev/null
  echo "OK"

  #############################################################################
  # Wait for the URL to be available
  #############################################################################
  echo -n "  - ArgoCD dashboard: "
  test_cmd="plnsvc_config kubectl get route/openshift-gitops-server --ignore-not-found -n $APP -o jsonpath={.spec.host}"
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

  # Allow ArgoCD to control resources outside of its namespace
  plnsvc_config oc adm policy add-cluster-role-to-user cluster-admin -z openshift-gitops-argocd-application-controller -n openshift-gitops >/dev/null

  # Log into ArgoCD
  echo -n "  - ArgoCD Login: "
  local argocd_password
  argocd_password="$(plnsvc_config kubectl get secret openshift-gitops-cluster -n openshift-gitops -o jsonpath="{.data.admin\.password}" | base64 --decode --ignore-garbage)"
  argocd_local login "$ARGOCD_HOSTNAME" --grpc-web --insecure --username admin --password "$argocd_password" >/dev/null
  echo "OK"
}

print_aliases() {
  echo "alias plnsvc_kubectl='KUBECONFIG=$KUBECONFIG_PLNSVC kubectl'"
  echo "alias kcp_kubectl='KUBECONFIG=$KUBECONFIG_KCP kubectl'"
  echo
}

main() {
  parse_args "$@"
  init

  for APP in ckcp openshift-gitops; do
    echo "[$APP]"
    install_"$(echo "$APP" | tr '-' '_')"
    echo
  done

  export KCP_ENV="dev"
  SCRIPT_DIR="$(cd $SCRIPT_DIR/../kcp >/dev/null; pwd)"
  export SCRIPT_DIR
  configure_kcp_cluster
  configure_pipeline_cluster
  register_clusters
  install_apps

  print_aliases

  export KCP_ENV="dev"
  SCRIPT_DIR="$(cd $SCRIPT_DIR/../kcp >/dev/null; pwd)"
  export SCRIPT_DIR
  configure_kcp_cluster
  configure_pipeline_cluster
  register_clusters
  install_apps
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi
