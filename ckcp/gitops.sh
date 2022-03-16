#!/usr/bin/env bash

#quit if exit status of any cmd is a non-zero value
set -euo pipefail
# set -x

SCRIPT_DIR="$(cd "$(dirname "$0")" >/dev/null ; pwd)"
GITOPS_DIR="$(dirname "$SCRIPT_DIR")/gitops"
WORK_DIR="$SCRIPT_DIR/work"
KUBECONFIG_CLUSTER="${KUBECONFIG:-$HOME/.kube/config}"
KUBECONFIG_KCP="$WORK_DIR/kubeconfig/admin.kubeconfig"
KUBECONFIG_MERGED="merged-config.kubeconfig:$KUBECONFIG_CLUSTER:$KUBECONFIG_KCP"



usage(){
  echo "
Usage:
    ${0##*/} [options]

Setup the pipeline service on a cluster running on KCP.

Optional arguments:
    -a, --app APP
        Install APP in the cluster. APP must be in [tekton-pipeline, pipelines].
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
  APP_LIST="openshift-gitops ckcp"

  local args
  args="$(getopt -o dha: -l "debug,help,app,all" -n "$0" -- "$@")"
  eval set -- "$args";
  while true; do
    case $1 in
      -a|--app)
        APP_LIST="$APP_LIST $2"
        shift
        ;;
      --all)
        APP_LIST="openshift-gitops ckcp tekton-pipeline pipelines"
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



install_openshift_gitops(){
  APP="openshift-gitops"
  export KUBECONFIG="$KUBECONFIG_CLUSTER"

  local ns="openshift-operators"

  #############################################################################
  # Install the gitops operator
  #############################################################################
  echo -n "  - OpenShift-GitOps: "
  if ! oc get subscriptions -n "$ns" openshift-gitops-operator >/dev/null 2>&1; then
    oc apply -f "$GITOPS_DIR/$APP.yaml" --wait >/dev/null
  fi
  echo "OK"

  #############################################################################
  # Wait for the URL to be available
  #############################################################################
  echo -n "  - ArgoCD dashboard: "
  test_cmd="oc get route/openshift-gitops-server --ignore-not-found -n $APP -o jsonpath={.spec.host}"
  ARGOCD_HOSTNAME="$(${test_cmd[@]})"
  until curl --fail --insecure --output /dev/null --silent "https://$ARGOCD_HOSTNAME"; do
    echo -n "."
    sleep 2
    ARGOCD_HOSTNAME="$(${test_cmd[@]})"
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
}


install_ckcp(){
  APP="ckcp"
  export KUBECONFIG="$KUBECONFIG_CLUSTER"

  local ns="$APP"
  local kube_dir="$WORK_DIR/kubeconfig"
  local test_cmd

  #############################################################################
  # Deploy KCP
  #############################################################################
  echo -n "  - $APP application: "
  if ! oc get apps -n openshift-gitops "$APP" >/dev/null 2>&1; then
    mkdir -p "$kube_dir"
    if [ -e "$KUBECONFIG_KCP" ]; then
      rm "$KUBECONFIG_KCP"
    fi
    oc apply -f "$GITOPS_DIR/$APP.yaml" --wait >/dev/null
  fi
  argocd app wait "$APP" >/dev/null
  echo "OK"

  #############################################################################
  # Wait for KCP to be online
  #############################################################################
  local podname
  echo -n "  - KCP pod: "
  test_cmd="oc get pods --ignore-not-found -n $ns -l=app=kcp-in-a-pod -o jsonpath={.items[0].metadata.name}"
  podname=$(${test_cmd[@]})
  while [ -z "$podname" ]; do
    echo -en "?\b"
    sleep 1
    echo -en " \b"
    sleep 1
    podname=$(${test_cmd[@]})
  done
  until oc wait --for=condition=Ready "pod/$podname" -n "$APP" --timeout=2s >/dev/null 2>&1; do
    echo -n "."
  done
  echo "OK"

  #############################################################################
  # Post install
  #############################################################################
  # Copy the kubeconfig of kcp from inside the pod onto the local filesystem
  if [ ! -e "$KUBECONFIG_KCP" ]; then
    oc cp "$APP/$podname:/workspace/.kcp/admin.kubeconfig" "$KUBECONFIG_KCP" >/dev/null
  fi

  # Check if external ip is assigned and replace kcp's external IP in the kubeconfig file
  echo -n "  - External IP: "
  if grep -q "localhost" "$KUBECONFIG_KCP"; then
    local route
    route=$(oc get route ckcp -n "$APP" -o jsonpath='{.spec.host}')
    sed -i "s/localhost:6443/$route:443/g" $KUBECONFIG_KCP
  fi
  echo "OK"

  # Make sure access to kcp-in-a-pod is good
  echo -n "  - KCP api-server: "
  KUBECONFIG="$KUBECONFIG_KCP" oc config set-cluster admin --insecure-skip-tls-verify=true >/dev/null
  test_cmd=""
  until KUBECONFIG="$KUBECONFIG_KCP" oc api-resources >/dev/null 2>&1; do
    echo -n "."
    sleep 2
  done
  echo "OK"

  # Create secret
  echo -n "  - Register KCP secret to host cluster: "
  if ! oc get namespace pipelines >/dev/null 2>&1; then
    echo -n "."
    oc create namespace pipelines >/dev/null
  fi
  if ! oc get secret ckcp-kubeconfig -n pipelines >/dev/null 2>&1; then
    echo -n "."
    oc create secret generic ckcp-kubeconfig -n pipelines --from-file "$KUBECONFIG_KCP" >/dev/null
  fi
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
    KUBECONFIG="$KUBECONFIG_KCP" oc create -f "$SCRIPT_DIR/../workspace.yaml"
  fi
  echo "OK"

  # Register the KCP cluster into ArgoCD
  export KUBECONFIG="$KUBECONFIG_MERGED"
  echo -n "  - ArgoCD KCP registration: "
  if ! argocd cluster get kcp >/dev/null 2>&1; then

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
    argocd cluster add admin_kcp --name=kcp --yes >/dev/null 2>&1
  fi
  echo "OK"
}


install_tekton_pipeline(){
  APP="tekton-pipeline"
  export KUBECONFIG="$KUBECONFIG_CLUSTER"

  #############################################################################
  # Install the tekton-pipeline application
  #############################################################################
  echo -n "  - $APP application: "
  if ! oc get apps -n openshift-gitops "$APP" >/dev/null 2>&1; then
    oc apply -f "$GITOPS_DIR/$APP.yaml" --wait >/dev/null
  fi
  argocd app wait $APP >/dev/null
  echo "OK"
}


install_pipelines(){
  APP="pipelines"
  export KUBECONFIG="$KUBECONFIG_CLUSTER"

  #############################################################################
  # Install the pipelines application
  #############################################################################
  echo -n "  - $APP application: "
  if ! oc get apps -n openshift-gitops "$APP" >/dev/null 2>&1; then
    oc apply -f "$GITOPS_DIR/$APP.yaml" --wait >/dev/null
  fi
  argocd app wait "$APP" >/dev/null
  echo "OK"
}


install_triggers_crds(){
  APP="triggers-crds"
  export KUBECONFIG="$KUBECONFIG_CLUSTER"

  #############################################################################
  # Install triggers CRDs
  #############################################################################
  echo -n "  - $APP application: "
  if ! oc get apps -n openshift-gitops "$APP" >/dev/null 2>&1; then
    oc apply -f "$GITOPS_DIR/$APP.yaml" --wait >/dev/null
  fi
  argocd app wait $APP >/dev/null
  echo "OK"
}


install_triggers_interceptors(){
  APP="triggers-interceptors"
  export KUBECONFIG="$KUBECONFIG_CLUSTER"

  #############################################################################
  # Create kcp-kubeconfig secrets for event listener and interceptors so that they can talk to KCP
  #############################################################################
  if ! KUBECONFIG=$KUBECONFIG_KCP oc get secret kcp-kubeconfig >/dev/null 2>&1; then
    KUBECONFIG=$KUBECONFIG_KCP oc create secret generic kcp-kubeconfig --from-file "$KUBECONFIG_KCP" >/dev/null
  fi
  if ! KUBECONFIG=$KUBECONFIG_KCP oc get secret kcp-kubeconfig -n tekton-pipelines >/dev/null 2>&1; then
    KUBECONFIG=$KUBECONFIG_KCP oc create secret generic kcp-kubeconfig -n tekton-pipelines --from-file "$KUBECONFIG_KCP" >/dev/null
  fi

  #############################################################################
  # Install triggers interceptors
  #############################################################################
  echo -n "  - $APP application: "
  if ! oc get apps -n openshift-gitops "$APP" >/dev/null 2>&1; then
    oc apply -f "$GITOPS_DIR/$APP.yaml" --wait >/dev/null
  fi
  argocd app wait $APP >/dev/null
  echo "OK"
}

install_triggers_controller(){
  APP="triggers-controller"
  export KUBECONFIG="$KUBECONFIG_CLUSTER"

  #############################################################################
  # Create kcp-kubeconfig secret for triggers controller
  #############################################################################
  if ! oc get namespace triggers >/dev/null 2>&1; then
    oc create namespace triggers >/dev/null
  fi
  if ! oc get secret ckcp-kubeconfig -n triggers >/dev/null 2>&1; then
    oc create secret generic ckcp-kubeconfig -n triggers --from-file "$KUBECONFIG_KCP" >/dev/null
  fi

  #############################################################################
  # Install triggers controller
  #############################################################################
  echo -n "  - $APP application: "

  if ! oc get apps -n openshift-gitops "$APP" >/dev/null 2>&1; then
    oc apply -f "$GITOPS_DIR/$APP.yaml" --wait >/dev/null
  fi
  argocd app wait "$APP" >/dev/null
  echo "OK"
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
