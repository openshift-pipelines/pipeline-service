#!/usr/bin/env bash

#quit if exit status of any cmd is a non-zero value
set -euo pipefail
# set -x

SCRIPT_DIR="$(cd "$(dirname "$0")" >/dev/null ; pwd)"
GITOPS_DIR="$(dirname "$SCRIPT_DIR")/gitops"
WORK_DIR="$SCRIPT_DIR/work"
KUBECONFIG=${KUBECONFIG:-$HOME/.kube/config}
KUBECONFIG_KCP="$WORK_DIR/kubeconfig/admin.kubeconfig"
KUBECONFIG_MERGED="merged-config.kubeconfig:$KUBECONFIG:$KUBECONFIG_KCP"


usage(){
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



parse_args(){
  local default_list="openshift-gitops ckcp"
  local pipeline_list="pipelines_crds pipelines_controller"
  local trigger_list="triggers_crds triggers_interceptors triggers_controller"
  APP_LIST="$default_list"

  local args
  args="$(getopt -o dha: -l "debug,help,app,all" -n "$0" -- "$@")"
  eval set -- "$args";
  while true; do
    case $1 in
      -a|--app)
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
      -d|--debug)
        set -x
        ;;
      -h|--help)
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



check_cluster_role(){
  if [ "$(oc auth can-i '*' '*' --all-namespaces)" != "yes" ]; then
    echo
    echo "[ERROR] User '$(oc whoami)' does not have the required 'cluster-admin' role." 1>&2
    echo "Log into the cluster with a user with the required privileges (e.g. kubeadmin) and retry."
    exit 1
  fi
}

install_app(){
  APP="$1"

  echo -n "  - $APP application: "
  oc apply -f "$GITOPS_DIR/$APP.yaml" --wait >/dev/null
  argocd app wait "$APP" >/dev/null
  echo "OK"
}

install_openshift_gitops(){
  APP="openshift-gitops"

  local ns="openshift-operators"

  #############################################################################
  # Install the gitops operator
  #############################################################################
  echo -n "  - OpenShift-GitOps: "
  oc apply -f "$GITOPS_DIR/$APP.yaml" --wait >/dev/null
  echo "OK"

  #############################################################################
  # Wait for the URL to be available
  #############################################################################
  echo -n "  - ArgoCD dashboard: "
  test_cmd="oc get route/openshift-gitops-server --ignore-not-found -n $APP -o jsonpath={.spec.host}"
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
  oc adm policy add-cluster-role-to-user cluster-admin -z openshift-gitops-argocd-application-controller -n openshift-gitops >/dev/null

  # Log into ArgoCD
  echo -n "  - ArgoCD Login: "
  local argocd_password
  argocd_password="$(oc get secret openshift-gitops-cluster -n openshift-gitops -o jsonpath="{.data.admin\.password}" | base64 --decode --ignore-garbage)"
  argocd login "$ARGOCD_HOSTNAME" --grpc-web --insecure --username admin --password "$argocd_password" >/dev/null
  echo "OK"

  # Register the host cluster as pipeline-cluster
  local cluster_name="pipeline-cluster"
  echo -n "  - Register cluster to ArgoCD as '$cluster_name': "
  if ! KUBECONFIG="$KUBECONFIG_MERGED" argocd cluster get $cluster_name >/dev/null 2>&1; then
    argocd cluster add "$(cat "$KUBECONFIG" | yq ".current-context")" --name="$cluster_name" --upsert --yes >/dev/null 2>&1
  fi
  echo "OK"
}


install_ckcp(){
  APP="ckcp"

  local ns="$APP"
  local kube_dir="$WORK_DIR/kubeconfig"

  #############################################################################
  # Deploy KCP
  #############################################################################
  install_app $APP

  #############################################################################
  # Post install
  #############################################################################
  # Copy the kubeconfig of kcp from inside the pod onto the local filesystem
  podname=$(oc get pods --ignore-not-found -n $ns -l=app=kcp-in-a-pod -o jsonpath={.items[0].metadata.name})
  oc cp "$APP/$podname:/workspace/.kcp/admin.kubeconfig" "$KUBECONFIG_KCP" >/dev/null

  # Check if external ip is assigned and replace kcp's external IP in the kubeconfig file
  echo -n "  - Route: "
  if grep -q "localhost" "$KUBECONFIG_KCP"; then
    local route
    route=$(oc get route ckcp -n "$APP" -o jsonpath='{.spec.host}')
    sed -i "s/localhost:6443/$route:443/g" $KUBECONFIG_KCP
  fi
  echo "OK"

  # Make sure access to kcp-in-a-pod is good
  echo -n "  - KCP api-server: "
  KUBECONFIG="$KUBECONFIG_KCP" oc config set-cluster admin --insecure-skip-tls-verify=true >/dev/null
  until KUBECONFIG="$KUBECONFIG_KCP" oc api-resources >/dev/null 2>&1; do
    echo -n "."
    sleep 2
  done
  echo "OK"

  # Register the host cluster to KCP
  echo -n "  - Cluster registration: "
  if ! KUBECONFIG=$KUBECONFIG_KCP oc get cluster local >/dev/null 2>&1; then
    (curl --fail --silent https://raw.githubusercontent.com/kcp-dev/kcp/948dbe9565cc7da439c698875ca1fa78350c4530/contrib/examples/cluster.yaml; sed -e 's/^/    /' $KUBECONFIG) > "$kube_dir/cluster.yaml"
    KUBECONFIG="$KUBECONFIG_KCP" oc apply -f "$kube_dir/cluster.yaml" >/dev/null
    rm "$kube_dir/cluster.yaml"
  fi
  echo "OK"

  echo -n "  - Workspace: "
  if ! KUBECONFIG="$KUBECONFIG_KCP" oc get workspaces demo >/dev/null 2>&1; then
    KUBECONFIG="$KUBECONFIG_KCP" oc create -f "$SCRIPT_DIR/../workspace.yaml" &>/dev/null
  fi
  echo "OK"

  # Register the KCP cluster into ArgoCD
  echo -n "  - ArgoCD KCP registration: "
  if ! KUBECONFIG="$KUBECONFIG_MERGED" argocd cluster get kcp >/dev/null 2>&1; then

    # <workaround> See https://github.com/kcp-dev/kcp/issues/535
    # Manually create the serviceaccount and secret on the KCP cluster for ArgoCD to use
    local argocd_yaml="$kube_dir/argocd_kcp.yaml"
    local argocd_sa="argocd-manager"
    local argocd_ns="kube-system"
    echo "---
apiVersion: v1
kind: Secret
metadata:
  name: $argocd_sa
  namespace: $argocd_ns
  annotations:
    kubernetes.io/service-account.name: $argocd_sa
type: kubernetes.io/service-account-token
data:
  ca.crt: $(cat "$KUBECONFIG_KCP" | yq ".clusters.[0].cluster.certificate-authority-data")
  namespace: $(echo "$argocd_ns" | base64)
  token: $(cat "$KUBECONFIG_KCP" | yq ".users.[0].user.token" | tr -d '\n' | base64)
---
apiVersion: v1
kind: ServiceAccount
metadata:
  clusterName: admin
  name: $argocd_sa
  namespace: $argocd_ns
secrets:
- name: $argocd_sa" > "$argocd_yaml"
    KUBECONFIG="$KUBECONFIG_KCP" oc apply -f "$argocd_yaml" >/dev/null
    rm "$argocd_yaml"
    # </workaround>

    sed -i -e 's:admin$:admin_kcp:g' "$KUBECONFIG_KCP"
    KUBECONFIG="$KUBECONFIG_MERGED" argocd cluster add admin_kcp --name=kcp --yes >/dev/null 2>&1
  fi
  echo "OK"
}


install_pipelines_crds(){
  install_app pipelines-crds
}


install_pipelines_controller(){
  # Create kcp-kubeconfig secret for pipelines controller
  echo -n "  - Register KCP secret to host cluster: "
  oc create namespace pipelines --dry-run=client -o yaml | oc apply -f - --wait &>/dev/null
  oc create secret generic ckcp-kubeconfig -n pipelines --from-file "$KUBECONFIG_KCP" --dry-run=client -o yaml | oc apply -f - --wait &>/dev/null
  echo "OK"

  install_app pipelines-controller
}


install_triggers_crds(){
  install_app triggers-crds
}


install_triggers_interceptors(){
  # Create kcp-kubeconfig secrets for event listener and interceptors so that they can talk to KCP
  oc create secret generic kcp-kubeconfig --from-file "$KUBECONFIG_KCP" --dry-run=client -o yaml | KUBECONFIG=$KUBECONFIG_KCP oc apply -f - --wait &>/dev/null
  oc create secret generic kcp-kubeconfig -n tekton-pipelines --from-file "$KUBECONFIG_KCP" --dry-run=client -o yaml | KUBECONFIG=$KUBECONFIG_KCP oc apply -f- --wait &>/dev/null

  install_app triggers-interceptors
}

install_triggers_controller(){
  # Create kcp-kubeconfig secret for triggers controller
  oc create namespace triggers -o yaml --dry-run=client | oc apply -f- --wait &>/dev/null
  oc create secret generic ckcp-kubeconfig -n triggers --from-file "$KUBECONFIG_KCP" --dry-run=client -o yaml | oc apply -f - --wait &>/dev/null

  install_app triggers-controller
}

main(){
  parse_args "$@"

  check_cluster_role
  for APP in $APP_LIST ; do
    echo "[$APP]"
    install_"$(echo $APP | tr '-' '_')"
    echo
  done
}


if [ "${BASH_SOURCE[0]}" == "$0" ]; then
    main "$@"
fi
