#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

install() {
  app="openshift-gitops"
  local ns="$app"

  #############################################################################
  # Install the gitops operator
  #############################################################################
  echo -n "- OpenShift-GitOps: "
  kubectl apply -k "$DEV_DIR/operators/$app" >/dev/null
  echo "OK"

  # Subscription information for potential debug
  mkdir -p "$WORK_DIR/logs/$app"
  kubectl get subscriptions $app-operator -n openshift-operators -o yaml >"$WORK_DIR/logs/$app/subscription.yaml"

  #############################################################################
  # Wait for the URL to be available
  #############################################################################
  echo -n "- Argo CD dashboard: "
  test_cmd="kubectl get route/openshift-gitops-server --ignore-not-found -n $ns -o jsonpath={.spec.host}"
  argocd_hostname="$(${test_cmd})"
  until curl --fail --insecure --output /dev/null --silent "https://$argocd_hostname"; do
    echo -n "."
    sleep 2
    argocd_hostname="$(${test_cmd})"
  done
  echo "OK"
  echo "- Argo CD URL: https://$argocd_hostname"

  #############################################################################
  # Post install
  #############################################################################
  # Log into Argo CD
  echo -n "- Argo CD Login: "
  local argocd_password
  argocd_password="$(kubectl get secret openshift-gitops-cluster -n $ns -o jsonpath="{.data.admin\.password}" | base64 --decode)"
  argocd login "$argocd_hostname" --grpc-web --insecure --username admin --password "$argocd_password" >/dev/null
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

main() {
  if [ -n "${DEBUG:-}" ]; then
    set -x
  fi
  install
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi
