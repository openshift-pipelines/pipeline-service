#!/usr/bin/env bash

#quit if exit status of any cmd is a non-zero value
set -euo pipefail
# set -x

SCRIPT_DIR="$(
  cd "$(dirname "$0")" >/dev/null
  pwd
)"

GITOPS_DIR="$(dirname "$SCRIPT_DIR")/gitops"
CKCP_DIR="$(dirname "$SCRIPT_DIR")/ckcp"
WORK_DIR="$SCRIPT_DIR/work"
KUBECONFIG=${KUBECONFIG:-$HOME/.kube/config}
KUBECONFIG_KCP="$WORK_DIR/kubeconfig/admin.kubeconfig"
KUBECONFIG_MERGED="merged-config.kubeconfig:$KUBECONFIG:$KUBECONFIG_KCP"
CR_TOSYNC=(
            conditions.tekton.dev
            pipelines.tekton.dev
            pipelineruns.tekton.dev
            pipelineresources.tekton.dev
            runs.tekton.dev
            tasks.tekton.dev
            repositories.pipelinesascode.tekton.dev
          )

usage() {
  echo "
Usage:
    ${0##*/} [options]

Setup the pipeline service on a cluster running on KCP.

Optional arguments:
    -a, --app APP
        Install APP in the cluster. APP must be pipelines.
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
  local pipeline_list="openshift-pipeline"
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
      *)
        echo "[ERROR] Unsupported app: $1" >&2
        usage
        exit 1
        ;;
      esac
      ;;
    --all)
      APP_LIST="$default_list $pipeline_list"
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

  echo -n "  - kcp: "
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
  echo "OK"

  # Check if external ip is assigned and replace kcp's external IP in the kubeconfig file
  echo -n "  - Route: "
  if grep -q "ckcp-ckcp.apps.domain.org" "$KUBECONFIG_KCP"; then
    yq e -i "(.clusters[].cluster.server) |= sub(\"ckcp-ckcp.apps.domain.org:6443\", \"$ckcp_route:443\")" "$KUBECONFIG_KCP"
  fi
  echo "OK"

  # Register the host cluster to KCP
  echo -n "  - Workspace: "
  # To ensure we are in demo's parent workspace to manipulate demo workspace
  KUBECONFIG="$KUBECONFIG_KCP"  kubectl kcp ws use root:default >/dev/null 2>&1
  if ! KUBECONFIG="$KUBECONFIG_KCP" kubectl get workspaces demo >/dev/null 2>&1; then
    KUBECONFIG="$KUBECONFIG_KCP" kubectl kcp workspaces create demo >/dev/null 2>&1
    # Check if workspace "demo" is ready. This is a workaround, because commands executed directly after creating workspace with "--enter" option occasionally fail
    while [[ $(KUBECONFIG="$KUBECONFIG_KCP" kubectl get workspace -o jsonpath='{.items[0].status.phase}') != "Ready" ]]; do
      echo -n "."
      sleep 5
    done
  fi
  KUBECONFIG="$KUBECONFIG_KCP" kubectl kcp workspaces use demo >/dev/null 2>&1
  echo "OK"

  echo -n "  - Workloadcluster pipeline-cluster registration: "
  if ! KUBECONFIG="$KUBECONFIG_KCP" kubectl get WorkloadCluster local >/dev/null 2>&1; then
    (
      kcp_image_tag="$(yq -e '.images[0].newTag' "$ckcp_dev_dir"/kustomization.yaml)"
      cr_string="$(IFS=,; echo "${CR_TOSYNC[*]}")"
      KUBECONFIG="$KUBECONFIG_KCP" kubectl kcp workload sync local \
      --syncer-image ghcr.io/kcp-dev/kcp/syncer:"$kcp_image_tag" \
      --resources "$cr_string" > "$kube_dir/syncer.yaml"
      kubectl apply -f "$kube_dir/syncer.yaml" >/dev/null 2>&1
      # Wait until Syncer pod is available
      SYNCER_NS_ID="$(kubectl get ns -l workload.kcp.io/workload-cluster=local -o json | jq -r '.items[0].metadata.name')"
      kubectl rollout status deployment/kcp-syncer -n "$SYNCER_NS_ID" --timeout=90s >/dev/null 2>&1
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

install_openshift_pipeline() {
  APP="argocd"

  echo -n "  - openshift-pipeline application: "
  kubectl apply -f "$GITOPS_DIR/$APP/$APP.yaml" --wait >/dev/null 2>&1
  argocd app wait pipelines-service tektoncd --timeout=90 >/dev/null 2>&1
  echo "OK"

  check_cr_sync
}

check_cr_sync() {
  # Wait until CRDs are synced to KCP
  echo -n "  - Sync CRDs to KCP: "
  local cr_regexp
  cr_regexp="$(IFS=\|; echo "${CR_TOSYNC[*]}")"
  local  wait_period=0
  while [[ "$(KUBECONFIG="$KUBECONFIG_KCP" kubectl api-resources -o name  2>&1 | grep -Ewc "$cr_regexp")" -ne ${#CR_TOSYNC[@]} ]]
  do
    wait_period=$((wait_period+10))
    #when timeout, print out the CR resoures that is not synced to KCP
    if [ $wait_period -gt 300 ];then
      echo "Failed to sync following resources to KCP: "
      cr_synced=$(KUBECONFIG="$KUBECONFIG_KCP" kubectl api-resources -o name)
      for cr in "${CR_TOSYNC[@]}"; do
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
